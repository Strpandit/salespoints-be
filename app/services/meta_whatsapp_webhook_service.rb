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
  rescue JSON::ParserError => e
    Rails.logger.error "MetaWhatsappWebhookService: Invalid JSON payload: #{e.message}"
    raise
  rescue StandardError => e
    Rails.logger.error "MetaWhatsappWebhookService: Error: #{e.message}"
    raise
  end

  private

  def process_messages(messages)
    messages.each do |message|

      case message["type"]
      when "button"
        process_button_reply(
          button_id: message.dig("button", "payload").to_s,
          from: message["from"].to_s
        )

      when "interactive"
        button_reply = message.dig("interactive", "button_reply")
        next unless button_reply.present?

        process_button_reply(
          button_id: button_reply["id"].to_s,
          from: message["from"].to_s
        )

      when "text"
        text_body = message.dig("text", "body").to_s.downcase.strip
        if text_body == "accept" || text_body == "accepts"
          process_text_accept(message["from"].to_s)
        elsif text_body == "reject" || text_body == "rejects"
          process_text_reject(message["from"].to_s)
        else
          Rails.logger.info "Unknown text message: #{text_body}"
        end
      end
    end
  end

  def process_text_accept(from)
    offer = find_latest_open_offer_for_phone(from)
    
    if offer.nil?
      send_text_acknowledgement(to: from, message: "No pending request found to accept.")
      return
    end

    unless can_respond?(offer)
      send_text_acknowledgement(to: from, message: "This request is no longer available for response.")
      return
    end

    handle_accept(offer, offer.b2b_order, offer.dealer, from)
  end

  def process_text_reject(from)
    offer = find_latest_open_offer_for_phone(from)
    
    if offer.nil?
      send_text_acknowledgement(to: from, message: "No pending request found to reject.")
      return
    end

    unless can_respond?(offer)
      send_text_acknowledgement(to: from, message: "This request is no longer available for response.")
      return
    end

    handle_reject(offer, offer.b2b_order, offer.dealer, from)
  end

  def find_latest_open_offer_for_phone(from)
    dealer = find_dealer_by_phone(from)
    return nil if dealer.nil?

    B2bOrderOffer
      .includes(:b2b_order)
      .where(dealer_id: dealer.id, status: "open")
      .where("b2b_orders.expires_at > ?", Time.current)
      .references(:b2b_order)
      .order(created_at: :desc)
      .first
  end

  def find_dealer_by_phone(from)
    normalized_from = from.to_s.gsub(/\D/, "")
    
    Dealer.find_by("REPLACE(phone, ' ', '') LIKE ?", "%#{normalized_from}") ||
    Dealer.find_by("REPLACE(phone, ' ', '') = ?", normalized_from)
  end

  def process_button_reply(button_id:, from:)
    offer = B2bOrderOffer.order(created_at: :desc).find_by(accept_token: button_id) ||
            B2bOrderOffer.order(created_at: :desc).find_by(reject_token: button_id)

    unless offer
      send_text_acknowledgement(to: from, message: "This request is invalid or expired.")
      return
    end

    dealer = offer.dealer
    order = offer.b2b_order

    unless sender_matches_dealer?(from: from, dealer: dealer)
      send_text_acknowledgement(to: from, message: "Your WhatsApp number is not authorized.")
      return
    end

    unless can_respond?(offer)
      send_text_acknowledgement(to: from, message: "This request is no longer available for response.")
      return
    end

    action = offer.accept_token == button_id ? "accept" : "reject"

    create_webhook_event(offer, from, action)

    if action == "accept"
      handle_accept(offer, order, dealer, from)
    elsif action == "reject"
      handle_reject(offer, order, dealer, from)
    else
      send_text_acknowledgement(to: from, message: "Unknown action.")
    end
  rescue StandardError => e
    send_text_acknowledgement(to: from, message: "Error: #{e.message}")
  end
  
  def can_respond?(offer)
    return false if offer.nil?
    return false unless offer.open?
    return false if offer.expired?
    return false if offer.b2b_order.accepted? if offer.b2b_order.respond_to?(:accepted?)
    
    order = offer.b2b_order

    if order.is_a?(Order)
      return false unless order.status == "pending"
      return false if order.seller_dealer_id.present?
      return false if order.expires_at.present? && Time.current > order.expires_at
      return true
    end

    return false if order.expired? if order.respond_to?(:expired?)
    return false unless order.request_status == "pending_request"
    return false unless order.status.in?(["pending_request", "pending_payment"])
    
    true
  end

  def handle_accept(offer, order, dealer, from)
    service = B2bOrderDealerResponseService.new(
      order: order,
      dealer: dealer,
      offer: offer
    )

    service.accept!

     message = if order.is_a?(Order)
      "✅ Order accepted! Customer has been notified."
    elsif order.is_direct_buy? && order.source_type == "WholesalerPost"
      "✅ Order accepted! Buyer has been notified."
    else
      "✅ Request accepted! Payment link sent to buyer."
    end

    send_text_acknowledgement(to: from, message: message)
    offer.update!(whatsapp_status: "replied")
  rescue StandardError => e
    send_text_acknowledgement(to: from, message: "❌ Failed to accept request: #{e.message}")
  end

  def handle_reject(offer, order, dealer, from)
    service = B2bOrderDealerResponseService.new(
      order: order,
      dealer: dealer,
      offer: offer
    )

    service.reject!

    send_text_acknowledgement(to: from, message: "❌ Order rejected.")
    offer.update!(whatsapp_status: "replied")
  rescue StandardError => e
    send_text_acknowledgement(to: from, message: "❌ Failed to reject request: #{e.message}")
  end

  def process_statuses(statuses)
    statuses.each do |status_entry|
      message_id = status_entry["id"].to_s
      next if message_id.blank?

      begin
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
        update_offer_status(offer, status_entry["status"])
      rescue ActiveRecord::RecordNotUnique
        Rails.logger.debug "Duplicate status event for message_id: #{message_id}"
      rescue StandardError => e
        Rails.logger.error "Failed to process status: #{e.message}"
        next
      end
    end
  end

  def update_offer_status(offer, status)
    attrs = { whatsapp_status: mapped_whatsapp_status(status) }
    attrs[:delivered_at] = Time.current if status == "delivered"
    attrs[:read_at] = Time.current if status == "read"

    if status == "failed"
      attrs[:failed_at] = Time.current
      attrs[:failure_reason] = "WhatsApp delivery failed"
    end

    offer.update!(attrs)
  end

  def create_webhook_event(offer, from, action)
    WhatsappWebhookEvent.create!(
      provider: "meta",
      event_type: "button_reply",
      event_key: "reply:#{SecureRandom.uuid}",
      direction: "inbound",
      b2b_order_offer: offer,
      notification: offer.notification,
      from_number: from,
      status: action,
      processed_at: Time.current,
      payload: {
        button_id: offer.accept_token,
        from: from,
        action: action,
        order_id: offer.b2b_order&.reference_number,
        dealer_id: offer.dealer&.id,
        order_type: offer.b2b_order&.source_type,
        is_wholesaler: offer.b2b_order&.is_direct_buy? && offer.b2b_order&.source_type == "WholesalerPost"
      }
    )
  end

  def send_text_acknowledgement(to:, message:)
    MetaWhatsappCloudService.new.send_text_message(
      to: normalized_e164_from_wa_id(to),
      body: message
    )
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