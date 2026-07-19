class OrderNotificationJob < ApplicationJob
  queue_as :default

  def perform(order_id, event, actor_type = nil, actor_id = nil)
    order = Order.includes(:buyer, :seller_dealer).find_by(id: order_id)
    return unless order

    actor = actor_type.present? && actor_id.present? ? actor_type.constantize.find_by(id: actor_id) : nil

    case event.to_s
    when "placed"
      notify_order_placed(order, actor)
    when "payment_paid"
      notify_payment_paid(order, actor)
    when "status_updated"
      notify_status_updated(order, actor)
    end
  end

  private

  def notify_order_placed(order, actor)
    create_notification(
      recipient: order.buyer,
      actor: actor,
      order: order,
      kind: "order_placed",
      title: "Order placed",
      message: "Your order #{order.order_number} has been placed successfully."
    )

    if order.seller_dealer.present?
      create_notification(
        recipient: order.seller_dealer,
        actor: actor,
        order: order,
        kind: "new_order",
        title: "New order received",
        message: "Order #{order.order_number} has been assigned to you."
      )
    end

    AdminUser.where(is_super_admin: true).find_each do |admin|
      create_notification(
        recipient: admin,
        actor: actor,
        order: order,
        kind: "admin_new_order",
        title: "New order placed",
        message: "Order #{order.order_number} was placed for Rs #{order.total_amount.to_f.round(2)}."
      )
    end
  end

  def notify_payment_paid(order, actor)
    create_notification(
      recipient: order.buyer,
      actor: actor,
      order: order,
      kind: "payment_paid",
      title: "Payment received",
      message: "Payment for order #{order.order_number} was confirmed."
    )

    create_notification(
      recipient: order.seller_dealer,
      actor: actor,
      order: order,
      kind: "payment_paid_seller",
      title: "Customer payment confirmed",
      message: "Payment for order #{order.order_number} has been confirmed."
    ) if order.seller_dealer.present?
  end

  def notify_status_updated(order, actor)
    create_notification(
      recipient: order.buyer,
      actor: actor,
      order: order,
      kind: "order_status_updated",
      title: "Order status updated",
      message: "Order #{order.order_number} is now #{order.status.to_s.humanize}."
    )

    AdminUser.where(is_super_admin: true).find_each do |admin|
      create_notification(
        recipient: admin,
        actor: actor,
        order: order,
        kind: "admin_order_status_updated",
        title: "Order status changed",
        message: "Order #{order.order_number} is now #{order.status.to_s.humanize}."
      )
    end

  end

  def create_notification(recipient:, actor:, order:, kind:, title:, message:)
    NotificationService.deliver(
      recipient: recipient,
      actor: actor,
      notifiable: order,
      kind: kind,
      title: title,
      message: message,
      payload: {
        order_id: order.id,
        order_number: order.order_number,
        total_amount: order.total_amount.to_f,
        status: order.status,
        payment_status: order.payment_status
      }
    )
  end
end
