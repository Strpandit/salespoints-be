class OrderRefundService
  Result = Struct.new(:order, :refund_payload, :dealer_balance, keyword_init: true)

  def initialize(order:, actor:, amount:, reason:, return_request: nil, refund_speed: "STANDARD")
    @order = order
    @actor = actor
    @amount = BigDecimal(amount.to_s).round(2)
    @reason = reason.to_s.strip
    @return_request = return_request
    @refund_speed = refund_speed.presence || "STANDARD"
  end

  def call
    raise StandardError, "Refund amount must be greater than 0" unless @amount.positive?

    Order.transaction do
      order = Order.lock.includes(:seller_dealer).find(@order.id)
      raise StandardError, "Order payment is not refundable" unless order.refundable?
      raise StandardError, "Refund amount exceeds remaining paid amount" if @amount > order.refundable_amount_remaining

      payload = create_gateway_refund!(order)
      apply_settlement_recovery!(order)
      order.mark_payment_refunded!(
        amount: @amount,
        gateway_payload: payload,
        reason: @reason.presence || "Refund initiated"
      )

      Result.new(
        order: order.reload,
        refund_payload: payload,
        dealer_balance: order.seller_dealer&.reload&.settlement_balance.to_d
      )
    end
  end

  private

  def create_gateway_refund!(order)
    return { "refund_amount" => @amount.to_f, "refund_status" => "MANUAL" } unless order.payment_method == "online"

    raise StandardError, "Cashfree order reference missing for refund" if order.gateway_order_reference.blank?

    CashfreeService.new.create_refund(
      order_reference: order.gateway_order_reference,
      refund_id: refund_id_for(order),
      amount: @amount,
      note: @reason.presence || "Refund for #{order.order_number}",
      refund_speed: @refund_speed
    )
  end

  def apply_settlement_recovery!(order)
    held_amount = order.settlement_status == "settled" ? 0.to_d : order.seller_settlement_amount.to_d
    deduction_from_hold = [@amount, held_amount].min
    extra_recovery = (@amount - deduction_from_hold).round(2)

    if deduction_from_hold.positive?
      remaining_settlement = (order.seller_settlement_amount.to_d - deduction_from_hold).round(2)
      order.update!(
        seller_settlement_amount: remaining_settlement,
        settlement_status: remaining_settlement.positive? ? "partially_refunded" : "refunded"
      )
    end

    return unless extra_recovery.positive? && order.seller_dealer.present?

    DealerLedgerService.debit!(
      dealer: order.seller_dealer,
      amount: extra_recovery,
      entry_type: "refund_adjustment",
      description: "Refund recovery for order #{order.order_number}",
      order: order,
      return_request: @return_request,
      metadata: {
        actor_type: @actor&.class&.name,
        actor_id: @actor&.id,
        reason: @reason
      }.compact
    )
  end

  def refund_id_for(order)
    "RF-#{order.order_number}-#{SecureRandom.hex(4).upcase}"
  end
end
