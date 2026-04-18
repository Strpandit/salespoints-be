class PushNotificationService
  FCM_LEGACY_URL = "https://fcm.googleapis.com/fcm/send".freeze

  def deliver(notification)
    channels = notification.delivery_channels
    return if channels.key?("push") && channels["push"] == false

    key = ENV["FCM_SERVER_KEY"].to_s
    return if key.blank?

    tokens = PushSubscription.where(subscriber: notification.receiver).distinct.pluck(:token)
    return if tokens.empty?

    tokens.each { |token| send_legacy_fcm(token, notification, key) }
  end

  private

  def send_legacy_fcm(device_token, notification, server_key)
    body = {
      to: device_token,
      notification: {
        title: notification.title.to_s.truncate(120),
        body: notification.body.to_s.truncate(240)
      },
      data: {
        notification_type: notification.notification_type.to_s,
        notification_id: notification.id.to_s
      }.merge(flat_string_data(notification.payload))
    }

    HTTParty.post(
      FCM_LEGACY_URL,
      headers: {
        "Authorization" => "key=#{server_key}",
        "Content-Type" => "application/json"
      },
      body: body.to_json,
      timeout: 10
    )
  rescue StandardError => e
  end

  def flat_string_data(payload)
    out = {}
    (payload || {}).each do |k, v|
      out[k.to_s] = v.is_a?(Hash) || v.is_a?(Array) ? v.to_json : v.to_s
    end
    out
  end
end
