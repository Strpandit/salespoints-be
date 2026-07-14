class BroadcastB2bOrderJob < ApplicationJob
  queue_as :broadcast

  def perform(order_id)
    order = B2bOrder.find_by(id: order_id)
    return unless order
    return if order.expired?
    return if order.accepted?
    return unless order.pending_request?

    service = B2bOrderBroadcastService.new(order: order, actor: order.buyer_dealer, is_b2c: false)
    service.incremental_broadcast!
  end
end