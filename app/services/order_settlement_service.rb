class OrderSettlementService
  Result = Struct.new(:order, :released_amount, :dealer_balance, keyword_init: true)

  def initialize(order:, actor: nil, force: false)
    @order = order
    @actor = actor
    @force = force
  end

  def call
    Order.transaction do
      order = Order.lock.includes(:seller_dealer).find(@order.id)
      refresh_due_dates!(order)
      raise StandardError, "Order is not ready for settlement" unless releasable?(order)

      amount = order.seller_settlement_amount.to_d.round(2)
      raise StandardError, "No seller settlement amount available" unless amount.positive?

      DealerLedgerService.credit!(
        dealer: order.seller_dealer,
        amount: amount,
        entry_type: "order_settlement",
        description: "Settlement released for order #{order.order_number}",
        order: order,
        metadata: {
          actor_type: @actor&.class&.name,
          actor_id: @actor&.id
        }.compact
      )

      order.update!(
        settlement_status: "settled",
        settled_at: Time.current,
        hold_released_at: Time.current
      )

      Result.new(
        order: order,
        released_amount: amount,
        dealer_balance: order.seller_dealer.reload.settlement_balance.to_d
      )
    end
  end

  def self.process_if_due!(order)
    return if order.blank?

    service = new(order: order)
    service.send(:refresh_due_dates!, order) if order.delivered_at.present?
    service.call if service.send(:releasable?, order.reload, auto_only: true)
  rescue StandardError
    nil
  end

  private

  def releasable?(order, auto_only: false)
    return false if order.seller_dealer.blank?
    return false unless order.payment_status.in?(%w[paid partially_refunded refunded])
    return false unless order.delivered?
    return false if order.active_return_request?
    return false unless order.seller_settlement_amount.to_d.positive?
    return false unless order.settlement_status.in?(%w[pending on_hold partially_refunded])

    due_at = order.settlement_due_at
    return @force unless due_at.present?

    return false if auto_only && @force

    due_at <= Time.current || @force
  end

  def refresh_due_dates!(order)
    return unless order.delivered_at.present?
    return if order.settlement_due_at.present? && order.return_window_closes_at.present?

    due_at = order.delivered_at + MarketplaceOrderFinancials.settlement_hold_days.days
    order.update!(
      settlement_due_at: due_at,
      return_window_closes_at: order.return_window_closes_at || (order.delivered_at + MarketplaceOrderFinancials.return_window_days.days),
      settlement_status: order.seller_settlement_amount.to_d.positive? ? "pending" : "refunded"
    )
  end
end
