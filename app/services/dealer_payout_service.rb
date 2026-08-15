class DealerPayoutService
  ACTIVE_PAYOUT_STATUSES = %w[pending approved processing paid].freeze
  PAYOUT_READY_ORDER_STATUSES = %w[delivered replacement_delivered].freeze
  PAYOUT_READY_PAYMENT_STATUSES = %w[paid].freeze

  GST_RATE_ON_COMMISSION = BigDecimal("0.18")

  COMMISSION_RATES = {
    b2b: BigDecimal("0.015"),
    b2c: BigDecimal("0.025"),
    wholesaler: BigDecimal("0.030")
  }.freeze

  def initialize(dealer:)
    @dealer = dealer
  end

  def summary_balances
    process_cod_commission_deductions!

    online_net_earned = calculate_total_net_online_sales
    cod_deduction_total = calculate_total_cod_deductions

    total_earnings = [online_net_earned - cod_deduction_total, 0.to_d].max.round(2)

    pending_payout = @dealer.dealer_payouts.where(status: %w[pending approved processing]).sum(:amount).to_d.round(2)
    paid_balance = @dealer.dealer_payouts.where(status: "paid").sum(:amount).to_d.round(2)

    eligible_rows = eligible_orders
    eligible_online_net = eligible_rows.sum { |row| BigDecimal(row[:net_payout_amount].to_s) }

    available_balance = [eligible_online_net - pending_payout, 0.to_d].max.round(2)

    {
      total_earnings: total_earnings.to_f,
      available_balance: available_balance.to_f,
      pending_payout: pending_payout.to_f,
      paid_balance: paid_balance.to_f,
      dealer_status: @dealer.status,
      bank_verified: @dealer.dealer_profile&.bank_verified? || false,
      eligible_orders_count: eligible_rows.length
    }
  end

  def eligible_orders
    retail_orders = Order
      .includes(:buyer, :seller_dealer, :return_requests)
      .where(seller_dealer_id: @dealer.id)
      .where(status: PAYOUT_READY_ORDER_STATUSES)
      .where(payment_status: PAYOUT_READY_PAYMENT_STATUSES)
      .where("delivered_at IS NOT NULL AND delivered_at <= ?", 48.hours.ago)
      .order(delivered_at: :desc)

    b2b_orders = B2bOrder
      .includes(:buyer_dealer, :seller_dealer, :return_requests)
      .where(seller_dealer_id: @dealer.id)
      .where(status: PAYOUT_READY_ORDER_STATUSES)
      .where(payment_status: PAYOUT_READY_PAYMENT_STATUSES)
      .where("delivered_at IS NOT NULL AND delivered_at <= ?", 48.hours.ago)
      .order(delivered_at: :desc)

    payload = []
    retail_orders.each { |order| append_eligible_order(payload, order) }
    b2b_orders.each { |order| append_eligible_order(payload, order) }
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
      parsed.each do |item|
        item_hash = item.is_a?(Hash) ? item.with_indifferent_access : {}
        oid = item_hash[:order_id] || item_hash[:id]
        otype = item_hash[:order_type] || item_hash[:type]
        ord = find_requestable(order_id: oid, order_type: otype)
        target_orders << ord if ord.present?
      end
    elsif order_id.present?
      ord = find_requestable(order_id: order_id, order_type: order_type)
      target_orders << ord if ord.present?
    end

    payout = nil

    Dealer.transaction do
      if target_orders.any?
        total_gross = 0.to_d
        total_commission = 0.to_d
        total_commission_gst = 0.to_d
        total_net_payout = 0.to_d
        order_summaries = []

        target_orders.each do |order|
          validate_requestable_eligibility!(order)
          breakdown = calculate_order_financials(order)

          total_gross += breakdown[:gross_amount]
          total_commission += breakdown[:commission_fee]
          total_commission_gst += breakdown[:commission_gst]
          total_net_payout += breakdown[:net_payout_amount]

          order_summaries << {
            order_id: order.id,
            order_type: requestable_type_param(order),
            reference_number: request_reference(order),
            flow_type: requestable_flow(order),
            buyer_name: buyer_name_for(order),
            gross_amount: breakdown[:gross_amount].to_f,
            commission_rate: (breakdown[:commission_rate] * 100).to_f,
            commission_fee: breakdown[:commission_fee].to_f,
            commission_gst: breakdown[:commission_gst].to_f,
            net_payout_amount: breakdown[:net_payout_amount].to_f,
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
            "total_commission_gst" => total_commission_gst.to_f,
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

    DealerPayoutMailer.request_created(payout.reload).deliver_later rescue nil
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
    DealerPayoutMailer.status_updated(payout.reload, actor: admin).deliver_later rescue nil
  end

  def reject!(payout:, admin:, note:)
    raise StandardError, "Only pending payouts can be rejected" unless payout.pending?

    payout.update!(
      status: "rejected",
      rejected_at: Time.current,
      approved_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutMailer.status_updated(payout.reload, actor: admin).deliver_later rescue nil
  end

  def mark_processing!(payout:, admin:, note: nil)
    raise StandardError, "Only approved payouts can move to processing" unless payout.approved?

    payout.update!(
      status: "processing",
      processing_at: Time.current,
      processed_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutMailer.status_updated(payout.reload, actor: admin).deliver_later rescue nil
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

      DealerPayoutMailer.payout_disbursed(locked_payout.reload).deliver_later rescue nil
    end
  end

  def mark_failed!(payout:, admin:, note:)
    payout.update!(
      status: "failed",
      processed_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutMailer.payout_failed(payout.reload, error_message: note).deliver_later rescue nil
  end

  def cancel!(payout:)
    raise StandardError, "Only pending payouts can be cancelled" unless payout.pending?

    payout.update!(
      status: "cancelled",
      cancelled_at: Time.current
    )
    DealerPayoutMailer.status_updated(payout.reload, actor: @dealer).deliver_later rescue nil
  end

  def calculate_order_financials(order)
    gross = gross_amount_for(order)
    rate = commission_rate_for(order)

    commission_fee = (gross * rate).round(2)
    commission_gst = (commission_fee * GST_RATE_ON_COMMISSION).round(2)
    net_payout = [gross - commission_fee - commission_gst, 0.to_d].max.round(2)

    {
      gross_amount: gross,
      commission_rate: rate,
      commission_fee: commission_fee,
      commission_gst: commission_gst,
      net_payout_amount: net_payout
    }
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
      deduction_total = breakdown[:commission_fee] + breakdown[:commission_gst]

      next if deduction_total <= 0

      DealerLedgerService.debit!(
        dealer: @dealer,
        amount: deduction_total,
        entry_type: "cod_commission_deduction",
        description: "COD Commission & GST deduction for order #{order.order_number}",
        order: order,
        metadata: {
          order_id: order.id,
          gross_amount: breakdown[:gross_amount].to_f,
          commission_fee: breakdown[:commission_fee].to_f,
          commission_gst: breakdown[:commission_gst].to_f
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

  def append_eligible_order(collection, requestable)
    return if requestable.try(:payment_method).to_s.downcase == "cod"

    eligibility = payout_eligibility_for(requestable)
    return unless eligibility[:eligible]

    breakdown = calculate_order_financials(requestable)

    collection << {
      order_id: requestable.id,
      order_type: requestable_type_param(requestable),
      requestable_type: requestable.class.name,
      reference_number: request_reference(requestable),
      flow_type: requestable_flow(requestable),
      buyer_name: buyer_name_for(requestable),
      gross_amount: breakdown[:gross_amount].to_f,
      commission_rate: (breakdown[:commission_rate] * 100).to_f,
      commission_fee: breakdown[:commission_fee].to_f,
      commission_gst: breakdown[:commission_gst].to_f,
      net_payout_amount: breakdown[:net_payout_amount].to_f,
      status: requestable.status,
      payment_status: requestable.payment_status,
      delivered_at: requestable.delivered_at&.iso8601
    }
  end

  def payout_eligibility_for(requestable)
    return { eligible: false, reason: "Order not found" } if requestable.blank?
    return { eligible: false, reason: "Unauthorized seller" } unless requestable.try(:seller_dealer_id) == @dealer.id
    return { eligible: false, reason: "Order must be delivered or replacement delivered" } unless requestable.status.to_s.in?(PAYOUT_READY_ORDER_STATUSES)
    return { eligible: false, reason: "Order payment must be verified as paid" } unless requestable.payment_status.to_s.in?(PAYOUT_READY_PAYMENT_STATUSES)
    return { eligible: false, reason: "Order is in the 48-hour hold window" } if requestable.delivered_at.blank? || requestable.delivered_at > 48.hours.ago
    return { eligible: false, reason: "COD orders cannot be directly requested for payout" } if requestable.try(:payment_method).to_s.downcase == "cod"
    return { eligible: false, reason: "Replacement request open" } if replacement_request_open?(requestable)
    return { eligible: false, reason: "Payout request already exists" } if active_payout_exists_for?(requestable)

    { eligible: true }
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

  def active_payout_exists_for?(requestable)
    DealerPayout
      .where(dealer_id: @dealer.id, requestable: requestable, status: ACTIVE_PAYOUT_STATUSES)
      .exists?
  end

  def find_requestable(order_id:, order_type:)
    return nil if order_id.blank? || order_type.blank?

    case order_type.to_s.downcase
    when "order", "b2c", "retail"
      Order.find_by(id: order_id, seller_dealer_id: @dealer.id)
    when "b2b", "wholesale", "b2b_order"
      B2bOrder.find_by(id: order_id, seller_dealer_id: @dealer.id)
    else
      raise StandardError, "Unsupported order type"
    end
  end

  def validate_requestable_eligibility!(requestable)
    eligibility = payout_eligibility_for(requestable)
    raise StandardError, eligibility[:reason] unless eligibility[:eligible]
  end

  def payout_metadata(profile, requestable, invoice_number, note)
    {
      dealer_profile_id: profile.id,
      business_name: profile.business_name,
      gst_number: profile.gst_number,
      note: note,
      invoice_number: invoice_number,
      bank_verified_at: profile.bank_verified_at&.iso8601,
      bank_verification_status: profile.bank_verification_status,
      requestable_type: requestable&.class&.name,
      requestable_id: requestable&.id,
      request_flow: requestable.present? ? requestable_flow(requestable) : "dealer_balance",
      order_reference: requestable.present? ? request_reference(requestable) : nil
    }.compact
  end

  def payout_ledger_metadata(payout)
    {
      payout_id: payout.id,
      request_number: payout.request_number,
      requestable_type: payout.requestable_type,
      requestable_id: payout.requestable_id,
      request_flow: payout.request_flow,
      order_reference: payout.order_reference
    }.compact
  end

  def request_reference(requestable)
    requestable.try(:order_number).presence || requestable.try(:reference_number).presence || "##{requestable.id}"
  end

  def requestable_type_param(requestable)
    requestable.is_a?(Order) ? "b2c" : "b2b"
  end

  def requestable_flow(requestable)
    return "b2c" if requestable.is_a?(Order)
    return "wholesaler" if requestable.is_a?(B2bOrder) && requestable.source_type == "WholesalerPost"

    "b2b"
  end

  def buyer_name_for(requestable)
    case requestable
    when Order
      buyer = requestable.buyer
      buyer.try(:full_name).presence || buyer.try(:first_name).presence || buyer.try(:dealer_code).presence || "Buyer"
    when B2bOrder
      buyer = requestable.buyer_dealer
      buyer.try(:full_name).presence || buyer.try(:dealer_code).presence || "Buyer"
    else
      "Buyer"
    end
  end
end
