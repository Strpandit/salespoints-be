class DealerPayoutService
  ACTIVE_PAYOUT_STATUSES = %w[pending approved processing paid].freeze
  PAYOUT_READY_ORDER_STATUSES = %w[delivered replacement_delivered].freeze

  def initialize(dealer:)
    @dealer = dealer
  end

  def eligible_orders
    retail_orders = Order
      .includes(:buyer, :seller_dealer, :return_requests)
      .where(seller_dealer_id: @dealer.id)
      .where(status: PAYOUT_READY_ORDER_STATUSES)
      .where(payment_status: "paid")
      .order(delivered_at: :desc)

    b2b_orders = B2bOrder
      .includes(:buyer_dealer, :seller_dealer, :return_requests)
      .where(seller_dealer_id: @dealer.id)
      .where(status: PAYOUT_READY_ORDER_STATUSES)
      .where(payment_status: "paid")
      .order(delivered_at: :desc)

    payload = []
    retail_orders.each { |order| append_eligible_order(payload, order) }
    b2b_orders.each { |order| append_eligible_order(payload, order) }
    payload.sort_by { |row| row[:delivered_at].to_s }.reverse
  end

  def request!(amount:, note: nil, order_id: nil, order_type: nil, invoice_number: nil, gst_invoice: nil)
    profile = @dealer.dealer_profile
    raise StandardError, "Dealer bank details are incomplete" if profile.blank? || profile.bank_name.blank? || profile.bank_account_number.blank? || profile.ifsc_code.blank?
    raise StandardError, "Please verify your bank account before requesting payout" unless profile.bank_verified?

    requestable = find_requestable(order_id: order_id, order_type: order_type)

    payout_amount =
      if requestable.present?
        raise StandardError, "GST invoice is required" if gst_invoice.blank?

        validate_requestable_eligibility!(requestable)
        payout_amount_for(requestable)
      else
        value = BigDecimal(amount.to_s).round(2)
        raise StandardError, "Payout amount must be greater than 0" unless value.positive?
        raise StandardError, "Insufficient settlement balance" if value > @dealer.settlement_balance.to_d
        value
      end

    payout = DealerPayout.create!(
      dealer: @dealer,
      requestable: requestable,
      amount: payout_amount,
      bank_name: profile.bank_name,
      bank_account_number: profile.bank_account_number,
      ifsc_code: profile.ifsc_code,
      account_holder_name: profile.account_holder_name.presence || @dealer.full_name.presence || profile.business_name,
      invoice_number: invoice_number.presence,
      admin_note: note,
      metadata: payout_metadata(profile, requestable, invoice_number, note)
    )

    payout.gst_invoice.attach(gst_invoice) if gst_invoice.present?
    DealerPayoutNotificationService.request_created!(payout.reload)
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
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin)
  end

  def reject!(payout:, admin:, note:)
    raise StandardError, "Only pending payouts can be rejected" unless payout.pending?

    payout.update!(
      status: "rejected",
      rejected_at: Time.current,
      approved_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin)
  end

  def mark_processing!(payout:, admin:, note: nil)
    raise StandardError, "Only approved payouts can move to processing" unless payout.approved?

    payout.update!(
      status: "processing",
      processing_at: Time.current,
      processed_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin)
  end

  def mark_paid!(payout:, admin:, payment_reference:, payment_mode:, note: nil)
    raise StandardError, "Only approved or processing payouts can be paid" unless payout.status.in?(%w[approved processing])

    Dealer.transaction do
      locked_payout = DealerPayout.lock.find(payout.id)
      locked_dealer = Dealer.lock.find(locked_payout.dealer_id)

      ensure_requestable_settlement_balance!(payout: locked_payout, dealer: locked_dealer)
      raise StandardError, "Dealer settlement balance is insufficient" if locked_payout.amount.to_d > locked_dealer.reload.settlement_balance.to_d

      DealerLedgerService.debit!(
        dealer: locked_dealer,
        amount: locked_payout.amount,
        entry_type: "payout_disbursement",
        description: "Payout disbursed for request #{locked_payout.request_number}",
        order: locked_payout.requestable.is_a?(Order) ? locked_payout.requestable : nil,
        metadata: payout_ledger_metadata(locked_payout).merge(
          payment_reference: payment_reference,
          payment_mode: payment_mode,
          admin_id: admin.id
        )
      )

      locked_payout.update!(
        status: "paid",
        paid_at: Time.current,
        processing_at: locked_payout.processing_at || Time.current,
        processed_by_admin: admin,
        payment_reference: payment_reference,
        payment_mode: payment_mode,
        admin_note: [locked_payout.admin_note, note].compact.join("\n").presence
      )
      DealerPayoutNotificationService.status_updated!(locked_payout.reload, actor: admin)
    end
  end

  def mark_failed!(payout:, admin:, note:)
    raise StandardError, "Only approved or processing payouts can fail" unless payout.status.in?(%w[approved processing])

    payout.update!(
      status: "failed",
      processed_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin)
  end

  def cancel!(payout:)
    raise StandardError, "Only pending payouts can be cancelled" unless payout.pending?

    payout.update!(
      status: "cancelled",
      cancelled_at: Time.current
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: @dealer)
  end

  def ensure_requestable_settlement_balance!(payout:, dealer:)
    requestable = payout.requestable
    return if requestable.blank?
    return if requestable_credit_exists?(dealer: dealer, requestable: requestable)

    amount = payout_amount_for(requestable)
    description = "Settlement released for payout request #{payout.request_number}"

    DealerLedgerService.credit!(
      dealer: dealer,
      amount: amount,
      entry_type: "order_settlement",
      description: description,
      order: requestable.is_a?(Order) ? requestable : nil,
      metadata: payout_ledger_metadata(payout).merge(
        invoice_number: payout.invoice_number,
        released_for_payout: true
      )
    )

    if requestable.is_a?(Order)
      requestable.update!(
        settlement_status: "settled",
        settled_at: requestable.try(:settled_at) || Time.current,
        hold_released_at: requestable.try(:hold_released_at) || Time.current
      )
    end
  end

  private

  def append_eligible_order(collection, requestable)
    eligibility = payout_eligibility_for(requestable)
    return unless eligibility[:eligible]

    collection << {
      order_id: requestable.id,
      order_type: requestable_type_param(requestable),
      requestable_type: requestable.class.name,
      reference_number: request_reference(requestable),
      flow_type: requestable_flow(requestable),
      buyer_name: buyer_name_for(requestable),
      amount: payout_amount_for(requestable).to_f,
      status: requestable.status,
      payment_status: requestable.payment_status,
      settlement_hold_until: settlement_hold_until_for(requestable)&.iso8601,
      delivered_at: requestable.delivered_at&.iso8601,
      replacement_request_open: false
    }
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

  def payout_eligibility_for(requestable)
    return { eligible: false, reason: "Order not found" } if requestable.blank?
    return { eligible: false, reason: "Unauthorized seller" } unless requestable.try(:seller_dealer_id) == @dealer.id
    return { eligible: false, reason: "Order must be delivered or replacement delivered before payout request" } unless requestable.status.to_s.in?(PAYOUT_READY_ORDER_STATUSES)
    return { eligible: false, reason: "Order payment must be completed before payout request" } unless payment_completed_for_payout?(requestable)
    return { eligible: false, reason: "Order is still in the 48-hour settlement hold window" } if settlement_hold_active?(requestable)
    return { eligible: false, reason: "Replacement request is still open for this order" } if replacement_request_open?(requestable)
    return { eligible: false, reason: "A payout request already exists for this order" } if active_payout_exists_for?(requestable)
    return { eligible: false, reason: "No payout amount available for this order" } unless payout_amount_for(requestable).positive?

    { eligible: true }
  end

  def payment_completed_for_payout?(requestable)
    case requestable
    when Order
      requestable.payment_status.in?(%w[paid partially_refunded refunded])
    when B2bOrder
      requestable.payment_status == "paid"
    else
      false
    end
  end

  def payout_amount_for(requestable)
    case requestable
    when Order
      value = requestable.seller_settlement_amount.to_d
      value.positive? ? value.round(2) : [requestable.total_amount.to_d - requestable.refund_amount.to_d, 0.to_d].max.round(2)
    when B2bOrder
      requestable.total_amount.to_d.round(2)
    else
      0.to_d
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

  def requestable_credit_exists?(dealer:, requestable:)
    scope = DealerLedgerEntry.where(
      dealer_id: dealer.id,
      entry_type: "order_settlement",
      direction: "credit"
    )

    if requestable.is_a?(Order)
      scope.where(order_id: requestable.id).exists?
    else
      scope.where("metadata ->> 'requestable_type' = ? AND metadata ->> 'requestable_id' = ?", requestable.class.name, requestable.id.to_s).exists?
    end
  end

  def settlement_hold_active?(requestable)
    hold_until = settlement_hold_until_for(requestable)
    hold_until.present? && hold_until > Time.current
  end

  def settlement_hold_until_for(requestable)
    if requestable.respond_to?(:settlement_due_at) && requestable.try(:settlement_due_at).present?
      requestable.settlement_due_at
    elsif requestable.delivered_at.present?
      requestable.delivered_at + 48.hours
    end
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
    return "wholesale" if requestable.is_a?(B2bOrder) && requestable.source_type == "WholesalerPost"

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
