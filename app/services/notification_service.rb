class NotificationService
  class << self
    def deliver(recipient:, kind:, title:, message:, notifiable: nil, actor: nil, payload: {}, visible_in_app: true, delivery_channels: {})
      return if recipient.blank?

      merged = payload.stringify_keys
      merged["visible_in_app"] = visible_in_app
      merged["delivery_channels"] = delivery_channels.stringify_keys if delivery_channels.present?
      if notifiable.present?
        merged["notifiable_type"] = notifiable.class.name
        merged["notifiable_id"] = notifiable.id
      end

      Notification.create!(
        receiver: recipient,
        actor: actor,
        notifiable: notifiable,
        notification_type: kind,
        title: title,
        body: message,
        payload: merged,
        sent_at: Time.current,
        read_at: nil
      )
    end
  end
end
