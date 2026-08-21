class DealerPayoutService
  ACTIVE_PAYOUT_STATUSES = %w[pending approved processing paid].freeze
  PAYOUT_READY_ORDER_STATUSES = %w[delivered replacement_delivered].freeze
  PAYOUT_READY_PAYMENT_STATUSES = %w[paid].freeze

  COMMISSION_RATES = {
    b2c: BigDecimal("0.025"),
    b2b: BigDecimal("0.015"),
    wholesaler: BigDecimal("0.015")
  }.freeze

  def initialize(dealer:)
    @dealer = dealer
  end

  def summary_balances
    process_cod_commission_deductions!

    online_net_earned = calculate_total_net_online_sales
    cod_gross = calculate_total_gross_cod_sales
    cod_deduction_total = calculate_total_cod_deductions

    total_earnings = [online_net_earned - cod_deduction_total, 0.to_d].max.round(2)

    pending_payout = @dealer.dealer_payouts.where(status: %w[pending approved processing]).sum(:amount).to_d.round(2)
    paid_balance = @dealer.dealer_payouts.where(status: "paid").sum(:amount).to_d.round(2)

    eligible_rows = eligible_orders
    eligible_online_rows = eligible_rows.select { |r| r[:payment_method].to_s.downcase != "cod" }
    eligible_cod_rows = eligible_rows.select { |r| r[:payment_method].to_s.downcase == "cod" }

    eligible_online_net = eligible_online_rows.sum { |row| BigDecimal(row[:net_payout_amount].to_s) }
    eligible_cod_commission = eligible_cod_rows.sum { |row| BigDecimal(row[:commission_fee].to_s) }

    available_balance = [eligible_online_net, 0.to_d].max.round(2)

    {
      total_earnings: total_earnings.to_f,
      available_balance: available_balance.to_f,
      pending_payout: pending_payout.to_f,
      paid_balance: paid_balance.to_f,
      prepaid_total_earnings: online_net_earned.to_f,
      prepaid_available_balance: eligible_online_net.to_f,
      postpaid_total_earnings: cod_gross.to_f,
      postpaid_commission_owed: cod_deduction_total.to_f,
      postpaid_available_balance: eligible_cod_commission.to_f,
      dealer_status: @dealer.status,
      bank_verified: @dealer.dealer_profile&.bank_verified? || false,
      eligible_orders_count: eligible_rows.length
    }
  end

  def eligible_orders
    claimed_keys = claimed_order_keys

    retail_orders = Order
      .includes(:buyer, :seller_dealer, :return_requests)
      .where(seller_dealer_id: @dealer.id)
      .where(status: PAYOUT_READY_ORDER_STATUSES)
      .where("payment_status = 'paid' OR payment_method = 'cod'")
      .where("delivered_at IS NOT NULL AND delivered_at <= ?", 48.hours.ago)
      .order(delivered_at: :desc)

    b2b_orders = B2bOrder
      .includes(:buyer_dealer, :seller_dealer, :return_requests)
      .where(seller_dealer_id: @dealer.id)
      .where(status: PAYOUT_READY_ORDER_STATUSES)
      .where("payment_status = 'paid' OR payment_method = 'cod'")
      .where("delivered_at IS NOT NULL AND delivered_at <= ?", 48.hours.ago)
      .order(delivered_at: :desc)

    payload = []
    retail_orders.each { |order| append_eligible_order(payload, order, claimed_keys: claimed_keys) }
    b2b_orders.each { |order| append_eligible_order(payload, order, claimed_keys: claimed_keys) }
    payload.sort_by { |row| row[:delivered_at].to_s }.reverse
  end

  def request!(amount: nil, note: nil, order_id: nil, order_type: nil, orders: nil, invoice_number: nil, gst_invoice: nil)
    raise StandardError, "Dealer account must be active to request payout" unless @dealer.active?

    profile = @dealer.dealer_profile
    raise StandardError, "Dealer bank details are incomplete" if profile.blank? || profile.bank_name.blank? || profile.bank_account_number.blank? || profile.ifsc_code.blank?
    raise StandardError, "Please verify your bank account before requesting payout" unless profile.bank_verified?

    target_orders = []

    if orders.present?
      parsed = orders.is_a?(String) ? (JSON.parse(orders) rescue []) : Array(orders)
      raise StandardError, "No orders specified in payout request" if parsed.empty?

      seen_keys = Set.new
      parsed.each do |item|
        item_hash = item.is_a?(Hash) ? item.with_indifferent_access : {}
        oid = item_hash[:order_id] || item_hash[:id]
        otype = item_hash[:order_type] || item_hash[:type]

        ord = find_requestable(order_id: oid, order_type: otype)
        raise StandardError, "Order ##{oid} (#{otype}) not found or does not belong to your account" unless ord.present?

        key = "#{ord.class.name}:#{ord.id}"
        if seen_keys.include?(key)
          raise StandardError, "Duplicate order detected: Order #{request_reference(ord)} is included multiple times in this request"
        end
        seen_keys.add(key)
        target_orders << ord
      end

      # Validate that orders do not mix Prepaid (Online) and Postpaid (COD) payment modes
      payment_modes = target_orders.map { |o| o.try(:payment_method).to_s.downcase == "cod" ? "cod" : "online" }.uniq
      if payment_modes.length > 1
        raise StandardError, "Cannot mix Prepaid (Online) and Postpaid (COD) orders in a single payout request. Please submit separate requests for Online and COD orders."
      end
    elsif order_id.present?
      ord = find_requestable(order_id: order_id, order_type: order_type)
      raise StandardError, "Order ##{order_id} not found or does not belong to your account" unless ord.present?
      target_orders << ord
    end

    # Enforce invoice number validation & uniqueness per dealer
    if invoice_number.present?
      cleaned_inv = invoice_number.to_s.strip
      existing_invoice = @dealer.dealer_payouts
                                .where("LOWER(TRIM(invoice_number)) = ?", cleaned_inv.downcase)
                                .where(status: ACTIVE_PAYOUT_STATUSES)
                                .exists?
      if existing_invoice
        raise StandardError, "Invoice number '#{cleaned_inv}' has already been submitted for an active or completed payout request."
      end
    end

    payout = nil

    Dealer.transaction do
      if target_orders.any?
        total_gross = 0.to_d
        total_commission = 0.to_d
        total_net_payout = 0.to_d
        order_summaries = []

        target_orders.each do |order|
          validate_requestable_eligibility!(order)
          breakdown = calculate_order_financials(order)

          total_gross += breakdown[:gross_amount]
          total_commission += breakdown[:commission_fee]
          total_net_payout += breakdown[:net_payout_amount]

          order_summaries << {
            order_id: order.id,
            order_type: requestable_type_param(order),
            reference_number: request_reference(order),
            flow_type: requestable_flow(order),
            buyer_name: buyer_name_for(order),
            payment_method: order.try(:payment_method).presence || "online",
            payment_status: order.try(:payment_status) || "paid",
            gross_amount: breakdown[:gross_amount].to_f,
            commission_rate: (breakdown[:commission_rate] * 100).to_f,
            commission_fee: breakdown[:commission_fee].to_f,
            net_payout_amount: breakdown[:net_payout_amount].to_f,
            created_at: order.created_at&.iso8601,
            delivered_at: order.delivered_at&.iso8601
          }
        end

        primary_requestable = target_orders.first

        payout = DealerPayout.create!(
          dealer: @dealer,
          requestable: primary_requestable,
          amount: total_net_payout.round(2),
          bank_name: profile.bank_name,
          bank_account_number: profile.bank_account_number,
          ifsc_code: profile.ifsc_code,
          account_holder_name: profile.account_holder_name.presence || @dealer.full_name.presence || profile.business_name,
          invoice_number: invoice_number.presence,
          admin_note: note,
          metadata: payout_metadata(profile, primary_requestable, invoice_number, note).merge(
            "selected_orders" => order_summaries,
            "order_count" => target_orders.length,
            "total_gross" => total_gross.to_f,
            "total_commission" => total_commission.to_f,
            "penalty" => 0.0,
            "net_payout" => total_net_payout.to_f
          )
        )
      else
        value = BigDecimal(amount.to_s).round(2)
        raise StandardError, "Payout amount must be greater than 0" unless value.positive?

        summary = summary_balances
        raise StandardError, "Insufficient available balance" if value > BigDecimal(summary[:available_balance].to_s)

        payout = DealerPayout.create!(
          dealer: @dealer,
          requestable: nil,
          amount: value,
          bank_name: profile.bank_name,
          bank_account_number: profile.bank_account_number,
          ifsc_code: profile.ifsc_code,
          account_holder_name: profile.account_holder_name.presence || @dealer.full_name.presence || profile.business_name,
          invoice_number: invoice_number.presence,
          admin_note: note,
          metadata: payout_metadata(profile, nil, invoice_number, note)
        )
      end

      payout.gst_invoice.attach(gst_invoice) if gst_invoice.present?
    end

    DealerPayoutNotificationService.request_created!(payout.reload) rescue nil
    payout
  end

  def approve!(payout:, admin:, note: nil)
    raise StandardError, "Only pending payouts can be approved" unless payout.pending?

    payout.update!(
      status: "approved",
      approved_at: Time.current,
      approved_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin) rescue nil
  end

  def reject!(payout:, admin:, note:)
    raise StandardError, "Only pending payouts can be rejected" unless payout.pending?

    payout.update!(
      status: "rejected",
      rejected_at: Time.current,
      approved_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin) rescue nil
  end

  def mark_processing!(payout:, admin:, note: nil)
    raise StandardError, "Only approved payouts can move to processing" unless payout.approved?

    payout.update!(
      status: "processing",
      processing_at: Time.current,
      processed_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin) rescue nil
  end

  def mark_paid!(payout:, admin:, payment_reference:, payment_mode:, note: nil, penalty: 0)
    raise StandardError, "Only pending, approved or processing payouts can be paid" unless payout.status.in?(%w[pending approved processing])

    penalty_val = BigDecimal(penalty.to_s).round(2)
    penalty_val = 0.to_d if penalty_val.negative?

    Dealer.transaction do
      locked_payout = DealerPayout.lock.find(payout.id)
      locked_dealer = Dealer.lock.find(locked_payout.dealer_id)

      final_amount = [locked_payout.amount.to_d - penalty_val, 0.to_d].max.round(2)

      DealerLedgerService.debit!(
        dealer: locked_dealer,
        amount: final_amount,
        entry_type: "payout_disbursement",
        description: "Payout disbursed for request #{locked_payout.request_number}#{penalty_val.positive? ? " (Penalty deducted: ₹#{penalty_val})" : ''}",
        order: locked_payout.requestable.is_a?(Order) ? locked_payout.requestable : nil,
        metadata: payout_ledger_metadata(locked_payout).merge(
          payment_reference: payment_reference,
          payment_mode: payment_mode,
          admin_id: admin.id,
          penalty: penalty_val.to_f
        )
      )

      locked_payout.update!(
        amount: final_amount,
        status: "paid",
        paid_at: Time.current,
        processing_at: locked_payout.processing_at || Time.current,
        processed_by_admin: admin,
        payment_reference: payment_reference,
        payment_mode: payment_mode,
        admin_note: [locked_payout.admin_note, note].compact.join("\n").presence,
        metadata: locked_payout.metadata.merge("penalty" => penalty_val.to_f)
      )

      DealerPayoutNotificationService.status_updated!(locked_payout.reload, actor: admin) rescue nil
    end
  end

  def mark_failed!(payout:, admin:, note:)
    payout.update!(
      status: "failed",
      processed_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin) rescue nil
  end

  def cancel!(payout:)
    raise StandardError, "Only pending payouts can be cancelled" unless payout.pending?

    payout.update!(
      status: "cancelled",
      cancelled_at: Time.current
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: @dealer) rescue nil
  end

  def calculate_order_financials(order)
    gross = gross_amount_for(order)
    rate = commission_rate_for(order)

    commission_fee = (gross * rate).round(2)
    net_payout = [gross - commission_fee, 0.to_d].max.round(2)

    {
      gross_amount: gross,
      commission_rate: rate,
      commission_fee: commission_fee,
      net_payout_amount: net_payout
    }
  end

  def ensure_requestable_settlement_balance!(payout:, dealer:)
    payout_amount = payout.amount.to_d
    settlement_balance = dealer.reload.settlement_balance.to_d

    raise StandardError, "Dealer settlement balance is insufficient" if payout_amount > settlement_balance

    true
  end

  def claimed_order_keys
    keys = Set.new

    active_payouts = @dealer.dealer_payouts.where(status: ACTIVE_PAYOUT_STATUSES)
    active_payouts.each do |p|
      if p.requestable_id.present?
        type_key = p.requestable_type == "Order" ? "order" : "b2b_order"
        keys.add("#{type_key}:#{p.requestable_id}")
      end

      selected = (p.metadata || {})["selected_orders"]
      if selected.is_a?(Array)
        selected.each do |item|
          oid = item["order_id"] || item[:order_id] || item["id"]
          otype = (item["order_type"] || item[:order_type] || "order").to_s.downcase
          otype_key = otype.in?(%w[b2b b2b_order wholesale]) ? "b2b_order" : "order"
          keys.add("#{otype_key}:#{oid}") if oid.present?
        end
      end
    end

    keys
  end

  def find_active_payout_for_order(requestable)
    return nil if requestable.blank?

    oid = requestable.id
    otype = requestable.is_a?(Order) ? "order" : "b2b_order"
    full_type = requestable.class.name

    # 1. Direct polymorphic match
    direct = @dealer.dealer_payouts.where(
      requestable_type: full_type,
      requestable_id: oid,
      status: ACTIVE_PAYOUT_STATUSES
    ).first
    return direct if direct.present?

    # 2. Check JSONB metadata array of selected_orders
    json_candidates = @dealer.dealer_payouts.where(status: ACTIVE_PAYOUT_STATUSES)
                             .where("metadata -> 'selected_orders' IS NOT NULL")
    json_candidates.find do |p|
      orders = (p.metadata || {})["selected_orders"] || []
      orders.any? do |item|
        item_id = item["order_id"] || item[:order_id] || item["id"]
        item_type = (item["order_type"] || item[:order_type] || "order").to_s.downcase
        item_type_normalized = item_type.in?(%w[b2b b2b_order wholesale]) ? "b2b_order" : "order"

        item_id.to_i == oid.to_i && item_type_normalized == otype
      end
    end
  end

  def active_payout_exists_for?(requestable)
    find_active_payout_for_order(requestable).present?
  end

  def validate_requestable_eligibility!(requestable)
    eligibility = payout_eligibility_for(requestable)
    unless eligibility[:eligible]
      ref = request_reference(requestable)
      existing = find_active_payout_for_order(requestable)
      if existing.present?
        status_text = existing.status == "paid" ? "has already been paid" : "has already been requested in payout #{existing.request_number} (#{existing.status.upcase})"
        raise StandardError, "Order #{ref} #{status_text} and cannot be requested again."
      else
        raise StandardError, "Order #{ref} is not eligible for payout: #{eligibility[:reason]}"
      end
    end
  end

  private

  def process_cod_commission_deductions!
    cod_orders = Order
      .where(seller_dealer_id: @dealer.id)
      .where(status: PAYOUT_READY_ORDER_STATUSES)
      .where(payment_method: "cod")
      .where("delivered_at IS NOT NULL AND delivered_at <= ?", 48.hours.ago)

    cod_orders.each do |order|
      already_deducted = DealerLedgerEntry.where(
        dealer_id: @dealer.id,
        order_id: order.id,
        entry_type: "cod_commission_deduction"
      ).exists?

      next if already_deducted

      breakdown = calculate_order_financials(order)
      deduction_total = breakdown[:commission_fee]

      next if deduction_total <= 0

      DealerLedgerService.debit!(
        dealer: @dealer,
        amount: deduction_total,
        entry_type: "cod_commission_deduction",
        description: "COD Platform Commission deduction for order #{order.order_number}",
        order: order,
        metadata: {
          order_id: order.id,
          gross_amount: breakdown[:gross_amount].to_f,
          commission_fee: breakdown[:commission_fee].to_f
        }
      )
    end
  end

  def calculate_total_net_online_sales
    online_orders = Order
      .where(seller_dealer_id: @dealer.id)
      .where(status: PAYOUT_READY_ORDER_STATUSES)
      .where(payment_status: PAYOUT_READY_PAYMENT_STATUSES)
      .where.not(payment_method: "cod")
      .where("delivered_at IS NOT NULL AND delivered_at <= ?", 48.hours.ago)

    b2b_orders = B2bOrder
      .where(seller_dealer_id: @dealer.id)
      .where(status: PAYOUT_READY_ORDER_STATUSES)
      .where(payment_status: PAYOUT_READY_PAYMENT_STATUSES)
      .where("delivered_at IS NOT NULL AND delivered_at <= ?", 48.hours.ago)

    total = 0.to_d
    online_orders.each { |o| total += calculate_order_financials(o)[:net_payout_amount] }
    b2b_orders.each { |o| total += calculate_order_financials(o)[:net_payout_amount] }
    total.round(2)
  end

  def calculate_total_cod_deductions
    DealerLedgerEntry
      .where(dealer_id: @dealer.id, entry_type: "cod_commission_deduction")
      .sum(:amount).to_d.round(2)
  end

  def append_eligible_order(collection, requestable, claimed_keys: nil)
    eligibility = payout_eligibility_for(requestable, claimed_keys: claimed_keys)
    return unless eligibility[:eligible]

    breakdown = calculate_order_financials(requestable)
    pm = requestable.try(:payment_method).to_s.presence || "online"

    collection << {
      order_id: requestable.id,
      order_type: requestable_type_param(requestable),
      requestable_type: requestable.class.name,
      reference_number: request_reference(requestable),
      flow_type: requestable_flow(requestable),
      buyer_name: buyer_name_for(requestable),
      payment_method: pm,
      is_cod: pm.downcase == "cod",
      gross_amount: breakdown[:gross_amount].to_f,
      commission_rate: (breakdown[:commission_rate] * 100).to_f,
      commission_fee: breakdown[:commission_fee].to_f,
      net_payout_amount: breakdown[:net_payout_amount].to_f,
      status: requestable.status,
      payment_status: requestable.payment_status,
      delivered_at: requestable.delivered_at&.iso8601
    }
  end

  def payout_eligibility_for(requestable, claimed_keys: nil)
    return { eligible: false, reason: "Order not found" } if requestable.blank?
    return { eligible: false, reason: "Unauthorized seller" } unless requestable.try(:seller_dealer_id) == @dealer.id
    return { eligible: false, reason: "Order must be delivered or replacement delivered" } unless requestable.status.to_s.in?(PAYOUT_READY_ORDER_STATUSES)
    
    is_cod = requestable.try(:payment_method).to_s.downcase == "cod"
    unless is_cod || requestable.payment_status.to_s.in?(PAYOUT_READY_PAYMENT_STATUSES)
      return { eligible: false, reason: "Order payment must be verified as paid" }
    end

    return { eligible: false, reason: "Order is in the 48-hour hold window" } if requestable.delivered_at.blank? || requestable.delivered_at > 48.hours.ago
    return { eligible: false, reason: "Replacement request open" } if replacement_request_open?(requestable)

    order_key = "#{requestable.is_a?(Order) ? 'order' : 'b2b_order'}:#{requestable.id}"
    is_claimed = claimed_keys ? claimed_keys.include?(order_key) : active_payout_exists_for?(requestable)
    return { eligible: false, reason: "Payout request already exists or order already paid" } if is_claimed

    { eligible: true }
  end

  def calculate_total_gross_cod_sales
    cod_orders = Order
      .where(seller_dealer_id: @dealer.id)
      .where(status: PAYOUT_READY_ORDER_STATUSES)
      .where(payment_method: "cod")
      .where("delivered_at IS NOT NULL AND delivered_at <= ?", 48.hours.ago)

    total = 0.to_d
    cod_orders.each { |o| total += gross_amount_for(o) }
    total.round(2)
  end

  def gross_amount_for(requestable)
    case requestable
    when Order
      requestable.total_amount.to_d.round(2)
    when B2bOrder
      requestable.total_amount.to_d.round(2)
    else
      0.to_d
    end
  end

  def commission_rate_for(requestable)
    flow = requestable_flow(requestable)
    case flow
    when "wholesaler", "offermart"
      COMMISSION_RATES[:wholesaler]
    when "b2b"
      COMMISSION_RATES[:b2b]
    else
      COMMISSION_RATES[:b2c]
    end
  end

  def replacement_request_open?(requestable)
    requestable.return_requests.where(request_type: "replacement", status: ReturnRequest::ACTIVE_STATUSES).exists?
  end

  def find_requestable(order_id:, order_type:)
    return nil if order_id.blank? || order_type.blank?

    case order_type.to_s.downcase
    when "order", "b2c", "retail"
      Order.find_by(id: order_id, seller_dealer_id: @dealer.id)
    when "b2b", "wholesale", "b2b_order"
      B2bOrder.find_by(id: order_id, seller_dealer_id: @dealer.id)
    else
      raise StandardError, "Unsupported order type: #{order_type}"
    end
  end

  def requestable_type_param(requestable)
    requestable.is_a?(Order) ? "order" : "b2b_order"
  end

  def request_reference(requestable)
    case requestable
    when Order then requestable.order_number
    when B2bOrder then requestable.reference_number
    else "N/A"
    end
  end

  def requestable_flow(requestable)
    case requestable
    when Order
      "b2c"
    when B2bOrder
      (requestable.respond_to?(:wholesaler_post_id) && requestable.wholesaler_post_id.present?) || requestable.try(:source_type) == "WholesalerPost" ? "wholesaler" : "b2b"
    else
      "general"
    end
  end

  def buyer_name_for(requestable)
    case requestable
    when Order
      requestable.buyer&.full_name || "Customer"
    when B2bOrder
      requestable.buyer_dealer&.dealer_profile&.business_name || requestable.buyer_dealer&.full_name || "Dealer"
    else
      "Customer"
    end
  end

  def payout_metadata(profile, requestable, invoice_number, note)
    default_address = @dealer.try(:addresses)&.find_by(is_default: true) || @dealer.try(:addresses)&.first
    dealer_city = default_address&.city.presence
    dealer_pincode = @dealer.try(:pincode).presence || default_address&.postal_code.presence

    {
      "dealer_id" => @dealer.id,
      "dealer_code" => @dealer.dealer_code,
      "dealer_name" => @dealer.full_name,
      "dealer_email" => @dealer.email,
      "dealer_phone" => @dealer.phone,
      "business_name" => profile&.business_name,
      "business_email" => profile&.business_email,
      "business_contact_number" => profile&.business_contact_number,
      "city" => dealer_city,
      "pincode" => dealer_pincode,
      "bank_name" => profile&.bank_name,
      "bank_account_number" => profile&.bank_account_number,
      "ifsc_code" => profile&.ifsc_code,
      "account_holder_name" => profile&.account_holder_name.presence || @dealer.full_name.presence || profile&.business_name,
      "invoice_number" => invoice_number,
      "request_note" => note,
      "requestable_reference" => requestable ? request_reference(requestable) : nil,
      "request_flow" => requestable ? requestable_flow(requestable) : "general"
    }.compact
  end

  def payout_ledger_metadata(payout)
    profile = @dealer.dealer_profile
    {
      payout_id: payout.id,
      request_number: payout.request_number,
      dealer_id: @dealer.id,
      dealer_code: @dealer.dealer_code,
      dealer_name: @dealer.full_name,
      dealer_email: @dealer.email,
      dealer_phone: @dealer.phone,
      business_name: profile&.business_name,
      business_contact_number: profile&.business_contact_number,
      amount: payout.amount.to_f,
      bank_name: payout.bank_name,
      bank_account_number: payout.bank_account_number,
      ifsc_code: payout.ifsc_code,
      account_holder_name: payout.account_holder_name
    }.compact
  end
end

