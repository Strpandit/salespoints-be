class BroadcastB2bOrderJob < ApplicationJob
  queue_as :broadcast

  def perform(order_id)
    order = B2bOrder.find_by(id: order_id)
    return unless order

    service = B2bOrderBroadcastService.new(order: order, actor: order.buyer_dealer)
    service.initial_broadcast!
  rescue StandardError => e
    Rails.logger.error "BroadcastB2bOrderJob error for order #{order_id}: #{e.message}"
  end
end