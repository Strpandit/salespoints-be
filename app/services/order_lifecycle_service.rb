class OrderLifecycleService
  def initialize(order:, actor: nil, status_note: nil)
    @order = order
    @actor = actor
    @status_note = status_note
  end

  def transition!(next_status:)
    next_status = next_status.to_s
    raise StandardError, "Invalid status transition" unless @order.can_transition_to?(next_status)

    attrs = { status: next_status, status_note: @status_note.presence || @order.status_note }
    now = Time.current

    case next_status
    when "processing"
      attrs[:processing_at] = @order.processing_at || now
    when "shipped", "replacement_shipped"
      attrs[:shipped_at] = @order.shipped_at || now
    when "delivered", "replacement_delivered"
      delivered_at = @order.delivered_at || now
      attrs[:delivered_at] = delivered_at
      attrs[:return_window_closes_at] = delivered_at + MarketplaceOrderFinancials.return_window_days.days
      attrs[:settlement_due_at] = delivered_at + MarketplaceOrderFinancials.settlement_hold_days.days
      attrs[:settlement_status] = @order.seller_settlement_amount.to_d.positive? ? "pending" : "refunded"
    when "cancelled"
      attrs[:cancelled_at] = @order.cancelled_at || now
      InstantOrderRefundService.process_refund!(order: @order, reason: @status_note.presence || "Order cancelled")
    end

    @order.update!(attrs.compact)
    OrderSettlementService.process_if_due!(@order.reload)

    if @order.status == "shipped"
      EmailDispatcherService.retail_order_shipped(@order)
    elsif %w[delivered replacement_delivered].include?(@order.status)
      EmailDispatcherService.retail_order_delivered(@order)
    end

    @order
  end
end
