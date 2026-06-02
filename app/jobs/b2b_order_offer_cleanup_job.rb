class B2bOrderOfferCleanupJob < ApplicationJob
  queue_as :default

  def perform
    order_ids = B2bOrderOffer.expirable.distinct.pluck(:b2b_order_id)

    order_ids.each do |order_id|
      ActiveRecord::Base.transaction do
        order = B2bOrder.lock.find(order_id)
        order.b2b_order_offers.open_state.where.not(expires_at: nil).where("expires_at <= ?", Time.current).find_each do |offer|
          offer.update!(
            status: "expired",
            responded_at: Time.current,
            whatsapp_status: offer.whatsapp_status == "read" ? "read" : offer.whatsapp_status
          )
        end

        next unless order.b2b_order_items.open_items.exists?

        B2bOrderBroadcastService.new(order: order, actor: order.buyer_dealer).rebroadcast_remaining_items!
      end
    end
  end
end
