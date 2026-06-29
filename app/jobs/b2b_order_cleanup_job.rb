class B2bOrderCleanupJob < ApplicationJob
  queue_as :cleanup

  def perform
    expired_orders = B2bOrder.pending_requests.where("expires_at < ?", Time.current)

    expired_orders.find_each do |order|
      expire_order(order)
    end
  end

  private

  def expire_order(order)
    ActiveRecord::Base.transaction do
      order.expire!

      order.b2b_order_offers.open_state.update_all(
        status: "expired",
        responded_at: Time.current
      )

      send_expiry_notification(order)
      create_expiry_notification(order)

    rescue StandardError => e
      Rails.logger.error "Failed to expire order #{order.id}: #{e.message}"
    end
  end

  def send_expiry_notification(order)
    message = <<~TEXT
      ⏰ *Request Expired*
      
      Your request for #{order.b2b_order_items.first&.product_variant&.product&.name || 'product'} has expired.
      
      No dealer responded within the time limit.
      You can try again.
    TEXT

    MetaWhatsappCloudService.new.send_text_message(
      to: formatted_phone_for(order.buyer_dealer),
      body: message
    )
  rescue StandardError => e
    Rails.logger.error "Failed to send expiry notification: #{e.message}"
  end

  def create_expiry_notification(order)
    NotificationService.deliver(
      recipient: order.buyer_dealer,
      actor: order.buyer_dealer,
      notifiable: order,
      kind: "b2b_order_expired",
      title: "⏰ Request Expired",
      message: "Your request ##{order.id} has expired. No dealer responded within the time limit.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
      payload: {
        order_id: order.id,
        expires_at: order.expires_at
      }
    )
  end

  def formatted_phone_for(dealer)
    return nil if dealer.phone.blank?
    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
  end
end