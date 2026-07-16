class ExpireB2cOrderJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find_by(id: order_id)
    return unless order
    return unless order.status == "pending"
    return if order.seller_dealer_id.present?

    return if order.expires_at.present? && order.expires_at > Time.current

    order.update!(
      status: "cancelled",
      status_note: "No seller accepted the order within time",
      cancelled_at: Time.current
    )

    order.order_offers.open_state.update_all(
      status: "expired",
      responded_at: Time.current,
      whatsapp_status: "replied"
    )

    order.order_broadcast_trackers.pending.update_all(
      status: "expired"
    )

    NotificationService.deliver(
      recipient: order.buyer,
      actor: nil,
      notifiable: order,
      kind: "b2c_order_expired",
      title: "⏰ Order Expired",
      message: "Your order ##{order.order_number} has expired as not accepted it within time.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.order_number,
        status: "expired"
      }
    )

    MetaWhatsappCloudService.new.send_text_message(
      to: formatted_phone_for(order.buyer),
      body: "⏰ Your order ##{order.order_number} has expired as not accepted it within time. You can try again."
    )

    AdminUser.where(is_super_admin: true).find_each do |admin|
      NotificationService.deliver(
        recipient: admin,
        actor: nil,
        notifiable: order,
        kind: "admin_b2c_order_expired",
        title: "⏰ B2C Order Expired",
        message: "B2C Order ##{order.order_number} expired. No seller accepted.",
        visible_in_app: true,
        delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
        payload: {
          order_id: order.order_number,
          buyer_id: order.buyer_id,
          total_amount: order.total_amount.to_f
        }
      )
    end
  end

  private

  def formatted_phone_for(user)
    return nil if user.phone.blank?
    cc = user.country_code.presence || "+91"
    "#{cc}#{user.phone}".gsub(/\s+/, "")
  end
end