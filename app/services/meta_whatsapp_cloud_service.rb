require "net/http"
require "uri"
require "json"

class MetaWhatsappCloudService
  GRAPH_BASE = "https://graph.facebook.com".freeze

  def deliver(notification)
    return unless configured?

    channels = notification.delivery_channels
    return if channels.key?("whatsapp") && channels["whatsapp"] == false

    to = e164_for(notification.receiver)
    return if to.blank?

    if notification.notification_type == "b2b_order_request"
      send_b2b_request_message(to: to, notification: notification)
    else
      send_text_message(to: to, body: composed_text(notification))
    end
  rescue StandardError => e
    Rails.logger.error("Meta WhatsApp delivery failed for notification #{notification&.id}: #{e.message}")
    track_failure(notification, e.message)
  end

  def send_text_message(to:, body:)
    post_message!(
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: normalized_destination(to),
      type: "text",
      text: {
        preview_url: false,
        body: body.to_s.truncate(4_000)
      }
    )
  end

  def send_b2b_request_message(to:, notification:)
    offer = resolve_offer(notification)
    payload = notification.payload.stringify_keys
    items = offer&.delivery_payload.presence || Array(payload["items"])
    button_accept_id = offer&.accept_token.to_s
    button_reject_id = offer&.reject_token.to_s
    return if items.empty? || button_accept_id.blank? || button_reject_id.blank?

    body_lines = items.map do |item|
      name = item["product_name"].presence || item["variant_sku"].presence || "Item"
      quantity = item["quantity"].to_i
      price = item["unit_price"].to_f.round(2)
      "#{name} | Qty: #{quantity} | Price: Rs #{price}"
    end

    body_text = <<~TEXT.strip
      Nearby B2B request ##{payload["order_id"]}
      Buyer: #{payload["buyer_name"].presence || "Dealer"}
      Radius: #{payload["requested_radius_km"].to_i} km

      #{body_lines.join("\n")}
    TEXT

    response = post_message!(
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: normalized_destination(to),
      type: "interactive",
      interactive: {
        type: "button",
        body: { text: body_text.truncate(1_024) },
        footer: { text: "First valid acceptance wins." },
        action: {
          buttons: [
            {
              type: "reply",
              reply: { id: button_accept_id, title: "Accept" }
            },
            {
              type: "reply",
              reply: { id: button_reject_id, title: "Reject" }
            }
          ]
        }
      }
    )
    track_success(notification: notification, offer: offer, to: to, response: response)
  end

  def configured?
    access_token.present? && phone_number_id.present?
  end

  private

  def composed_text(notification)
    [notification.title, notification.body].compact.join("\n").truncate(4_000)
  end

  def access_token
    ENV["META_WHATSAPP_ACCESS_TOKEN"].to_s.presence
  end

  def phone_number_id
    ENV["META_WHATSAPP_PHONE_NUMBER_ID"].to_s.presence
  end

  def api_version
    ENV["META_WHATSAPP_API_VERSION"].to_s.presence || "v23.0"
  end

  def endpoint
    "#{GRAPH_BASE}/#{api_version}/#{phone_number_id}/messages"
  end

  def post_message!(payload)
    uri = URI(endpoint)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{access_token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload)

    response = http_client(uri).request(request)
    return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

    raise StandardError, "Meta WhatsApp API error #{response.code}: #{response.body}"
  end

  def resolve_offer(notification)
    offer_id = notification.payload["offer_id"]
    return nil if offer_id.blank?

    B2bOrderOffer.find_by(id: offer_id)
  end

  def track_success(notification:, offer:, to:, response:)
    message_id = Array(response["messages"]).first&.dig("id")
    conversation_id = Array(response["contacts"]).first&.dig("wa_id")

    if offer.present?
      offer.update!(
        whatsapp_message_id: message_id,
        whatsapp_status: "sent",
        recipient_phone: to,
        sent_at: Time.current
      )
    end

    WhatsappWebhookEvent.create!(
      provider: "meta",
      event_type: "outbound_message",
      event_key: "outbound:#{message_id.presence || SecureRandom.uuid}",
      direction: "outbound",
      b2b_order_offer: offer,
      notification: notification,
      message_id: message_id,
      conversation_id: conversation_id,
      to_number: normalized_destination(to),
      status: "sent",
      processed_at: Time.current,
      payload: response
    )
  end

  def track_failure(notification, message)
    offer = resolve_offer(notification)
    offer&.update!(whatsapp_status: "failed", failed_at: Time.current, failure_reason: message)
  rescue StandardError
    nil
  end

  def normalized_destination(to)
    to.to_s.delete_prefix("+")
  end

  def e164_for(receiver)
    phone = receiver.try(:phone).to_s.gsub(/\s+/, "")
    return nil if phone.blank?

    cc = receiver.try(:country_code).to_s.strip
    cc = "+91" if cc.blank?
    cc = "+#{cc.delete_prefix('+')}" unless cc.start_with?("+")

    combined = "#{cc}#{phone.gsub(/\A\+/, '')}"
    parsed = Phonelib.parse(combined)
    parsed.valid? ? parsed.e164 : nil
  end

  def http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 20
    http.open_timeout = 10
    http
  end
end
