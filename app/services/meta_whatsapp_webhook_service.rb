require "openssl"
require "json"

class MetaWhatsappWebhookService
  def initialize(headers:, raw_body:)
    @headers = headers
    @raw_body = raw_body.to_s
  end

  def call
    verify_signature! if app_secret.present?

    payload = JSON.parse(@raw_body)
    Array(payload["entry"]).each do |entry|
      Array(entry["changes"]).each do |change|
        value = change["value"] || {}
        process_messages(Array(value["messages"]))
        process_statuses(Array(value["statuses"]))
      end
    end
  end

  private

  def process_messages(messages)
    messages.each do |message|
      next unless message["type"] == "interactive"

      button_reply = message.dig("interactive", "button_reply")
      next unless button_reply.present?

      process_button_reply(
        button_id: button_reply["id"].to_s,
        from: message["from"].to_s
      )
    end
  end

  def process_button_reply(button_id:, from:)
    offer = B2bOrderOffer.order(created_at: :desc).find_by(accept_token: button_id) ||
            B2bOrderOffer.order(created_at: :desc).find_by(reject_token: button_id)

    unless offer
      send_text_acknowledgement(to: from, message: "This action is invalid or expired.")
      return
    end

    dealer = offer.dealer
    order = offer.b2b_order
    item_ids = offer.item_id_values
    action = offer.accept_token.to_s == button_id ? "accept" : "reject"

    WhatsappWebhookEvent.create!(
      provider: "meta",
      event_type: "button_reply",
      event_key: "reply:#{button_id}:#{from}:#{Time.current.to_f}",
      direction: "inbound",
      b2b_order_offer: offer,
      notification: offer.notification,
      from_number: from,
      status: action,
      processed_at: Time.current,
      payload: {
        button_id: button_id,
        from: from,
        action: action,
        order_id: order&.id,
        dealer_id: dealer&.id
      }
    )

    unless dealer && order
      send_text_acknowledgement(to: from, message: "This B2B request is no longer available.")
      return
    end

    unless sender_matches_dealer?(from: from, dealer: dealer)
      send_text_acknowledgement(to: from, message: "This WhatsApp number is not allowed for that dealer request.")
      return
    end

    if action == "accept"
      B2bOrderDealerResponseService.new(order: order, dealer: dealer, requested_ids: item_ids, offer: offer).accept!
      send_text_acknowledgement(to: from, message: "Selected B2B items have been accepted successfully.")
    elsif action == "reject"
      B2bOrderDealerResponseService.new(order: order, dealer: dealer, requested_ids: item_ids, offer: offer).reject!
      send_text_acknowledgement(to: from, message: "Selected B2B items have been rejected.")
    else
      send_text_acknowledgement(to: from, message: "Unsupported WhatsApp action.")
    end
  rescue StandardError => e
    send_text_acknowledgement(to: from, message: e.message)
  end

  def process_statuses(statuses)
    statuses.each do |status_entry|
      message_id = status_entry["id"].to_s
      next if message_id.blank?

      event = WhatsappWebhookEvent.create!(
        provider: "meta",
        event_type: "message_status",
        event_key: "status:#{message_id}:#{status_entry['status']}:#{status_entry['timestamp']}",
        direction: "inbound",
        message_id: message_id,
        conversation_id: status_entry.dig("conversation", "id"),
        from_number: status_entry["recipient_id"],
        status: status_entry["status"],
        processed_at: Time.current,
        payload: status_entry
      )

      offer = B2bOrderOffer.find_by(whatsapp_message_id: message_id)
      next unless offer

      event.update!(b2b_order_offer: offer)
      attrs = { whatsapp_status: mapped_whatsapp_status(status_entry["status"]) }
      attrs[:delivered_at] = Time.current if status_entry["status"] == "delivered"
      attrs[:read_at] = Time.current if status_entry["status"] == "read"
      if status_entry["status"] == "failed"
        attrs[:failed_at] = Time.current
        attrs[:failure_reason] = status_entry.dig("errors", 0, "title") || "WhatsApp delivery failed"
      end
      offer.update!(attrs)
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end

  def send_text_acknowledgement(to:, message:)
    MetaWhatsappCloudService.new.send_text_message(to: normalized_e164_from_wa_id(to), body: message)
  rescue StandardError => e
    Rails.logger.error("Meta WhatsApp acknowledgement failed: #{e.message}")
  end

  def normalized_e164_from_wa_id(wa_id)
    digits = wa_id.to_s.gsub(/\D/, "")
    digits.present? ? "+#{digits}" : wa_id
  end

  def sender_matches_dealer?(from:, dealer:)
    expected = e164_for(dealer)&.gsub(/\D/, "")
    actual = from.to_s.gsub(/\D/, "")
    expected.present? && actual.present? && expected == actual
  end

  def mapped_whatsapp_status(status)
    case status.to_s
    when "sent", "delivered", "read", "failed"
      status.to_s
    else
      "sent"
    end
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

  def verify_signature!
    signature = @headers["X-Hub-Signature-256"].to_s
    raise StandardError, "Missing Meta WhatsApp signature" if signature.blank?

    digest = OpenSSL::HMAC.hexdigest("SHA256", app_secret, @raw_body)
    expected = "sha256=#{digest}"
    unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)
      raise StandardError, "Invalid Meta WhatsApp signature"
    end
  end

  def app_secret
    ENV["META_WHATSAPP_APP_SECRET"].to_s.presence
  end
end
