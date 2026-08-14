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
        elsif text_body == "shipped" || text_body == "mark shipped" || text_body == "mark as shipped"
          process_text_shipped(message["from"].to_s)
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

    order = get_order_from_offer(offer)
    handle_accept(offer, order, offer.dealer, from)
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

    order = get_order_from_offer(offer)
    handle_reject(offer, order, offer.dealer, from)
  end

  def process_text_shipped(from)
    dealer = find_dealer_by_phone(from)
    return send_text_acknowledgement(to: from, message: "Dealer not found.") if dealer.nil?

    order = find_latest_accepted_order_for_dealer(dealer)
    
    if order.nil?
      send_text_acknowledgement(to: from, message: "No accepted order found to mark as shipped.")
      return
    end

    unless can_mark_shipped?(order)
      send_text_acknowledgement(to: from, message: "This order cannot be marked as shipped at this time.")
      return
    end

    handle_shipped(order, dealer, from)
  end

  def find_latest_accepted_order_for_dealer(dealer)
    order = B2bOrder
      .where(seller_dealer_id: dealer.id)
      .where(status: ["confirmed"])
      .where(shipped_at: nil)
      .where(delivered_at: nil)
      .order(accepted_at: :desc)
      .first

      if order.nil?
      order = Order
        .where(seller_dealer_id: dealer.id)
        .where(status: ["processing", "confirmed"])
        .where(shipped_at: nil)
        .where(delivered_at: nil)
        .order(accepted_at: :desc)
        .first
    end

    order
  end

  def can_mark_shipped?(order)
    return false if order.nil?
    
    if order.is_a?(Order)
      return false unless order.status.in?(["processing", "confirmed"])
      return false if order.shipped_at.present?
      return false if order.delivered_at.present?
      return true
    end

    if order.is_a?(B2bOrder)
      return false unless order.status.in?(["confirmed"])
      return false if order.shipped_at.present?
      return false if order.delivered_at.present?
      return true
    end

    false
  end

  def handle_shipped(order, dealer, from)
    begin
      if order.is_a?(B2bOrder)
        order.mark_shipped!
        
        EmailDispatcherService.b2b_order_shipped(order)
        
        delivery_confirmation = DeliveryConfirmationService.new(
          deliverable: order, 
          actor: dealer
        ).create_or_refresh!

        send_text_acknowledgement(
          to: from,
          message: "✅ Order ##{order.reference_number} has been marked as shipped! Delivery confirmation form sent to you."
        )
      elsif order.is_a?(Order)
        order.update!(
          status: "shipped",
          shipped_at: Time.current
        )
        
        EmailDispatcherService.retail_order_shipped(order)

        elivery_confirmation = DeliveryConfirmationService.new(
          deliverable: order,
          actor: dealer
        ).create_or_refresh!
        
        send_text_acknowledgement(
          to: from,
          message: "✅ Order ##{order.order_number} has been marked as shipped! Delivery confirmation form sent to you."
        )
      end

      create_shipped_webhook_event(order, from, dealer)
      
    rescue StandardError => e
      send_text_acknowledgement(to: from, message: "❌ Failed to mark as shipped: #{e.message}")
      Rails.logger.error "Failed to mark order as shipped via WhatsApp: #{e.message}"
    end
  end

  def create_shipped_webhook_event(order, from, dealer)
    WhatsappWebhookEvent.create!(
      provider: "meta",
      event_type: "order_shipped",
      event_key: "shipped:#{SecureRandom.uuid}",
      direction: "inbound",
      from_number: from,
      status: "shipped",
      processed_at: Time.current,
      payload: {
        dealer_id: dealer.id,
        order_id: order.id,
        order_type: order.is_a?(Order) ? "b2c" : "b2b",
        order_number: order.is_a?(Order) ? order.order_number : order.reference_number,
        shipped_at: Time.current
      }
    )
  end

  def find_latest_open_offer_for_phone(from)
    dealer = find_dealer_by_phone(from)
    return nil if dealer.nil?

    offer = OrderOffer
      .includes(:order)
      .where(dealer_id: dealer.id, status: "open")
      .where("orders.expires_at > ?", Time.current)
      .references(:order)
      .order(created_at: :desc)
      .first

    if offer.nil?
      offer = B2bOrderOffer
        .includes(:b2b_order)
        .where(dealer_id: dealer.id, status: "open")
        .where("b2b_orders.expires_at > ?", Time.current)
        .references(:b2b_order)
        .order(created_at: :desc)
        .first
    end

    offer
  end

  def find_dealer_by_phone(from)
    normalized_from = from.to_s.gsub(/\D/, "")
    
    Dealer.find_by("REPLACE(phone, ' ', '') LIKE ?", "%#{normalized_from}") ||
    Dealer.find_by("REPLACE(phone, ' ', '') = ?", normalized_from)
  end

  def process_button_reply(button_id:, from:)

    # ── Replacement request: accept / reject via signed token ──────────────
    replacement_payload = ReplacementRequestNotificationService.decode_token(button_id)
    if replacement_payload.present?
      handle_replacement_response(
        action: replacement_payload[:action],
        return_request_id: replacement_payload[:id],
        from: from
      )
      return
    end
    # ── End replacement handling ───────────────────────────────────────────

    offer = OrderOffer.order(created_at: :desc).find_by(shipped_token: button_id) ||
            B2bOrderOffer.order(created_at: :desc).find_by(shipped_token: button_id)

    if offer.present?
      dealer = offer.dealer
      order = get_order_from_offer(offer)

      unless sender_matches_dealer?(from: from, dealer: dealer)
        send_text_acknowledgement(to: from, message: "Your WhatsApp number is not authorized.")
        return
      end

      unless can_mark_shipped?(order)
        send_text_acknowledgement(to: from, message: "This order cannot be marked as shipped at this time.")
        return
      end

      handle_shipped(order, dealer, from)
      return
    end

    offer = OrderOffer.order(created_at: :desc).find_by(accept_token: button_id) ||
            OrderOffer.order(created_at: :desc).find_by(reject_token: button_id)

    if offer.nil?
      offer = B2bOrderOffer.order(created_at: :desc).find_by(accept_token: button_id) ||
              B2bOrderOffer.order(created_at: :desc).find_by(reject_token: button_id)
    end

    unless offer
      send_text_acknowledgement(to: from, message: "This request is invalid or expired.")
      return
    end

    dealer = offer.dealer
    order = get_order_from_offer(offer)

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
    
    if offer.is_a?(OrderOffer)
      order = offer.order
      return false unless order.is_a?(Order)
      return false unless order.status == "pending"
      return false if order.seller_dealer_id.present?
      return false if order.expires_at.present? && Time.current > order.expires_at
      # return false unless order.payment_status == "paid"
      return true
    end

    if offer.is_a?(B2bOrderOffer)
      order = offer.b2b_order
      return false if order.expired? if order.respond_to?(:expired?)
      return false if order.accepted? if order.respond_to?(:accepted?)
      return false unless order.request_status == "pending_request"
      return false unless order.status.in?(["pending_request", "pending_payment"])
      return true
    end

    false
  end

  def handle_replacement_response(action:, return_request_id:, from:)
    return_request = ReturnRequest.find_by(id: return_request_id)

    unless return_request
      send_text_acknowledgement(to: from, message: "❌ Replacement request not found or expired.")
      return
    end

    unless return_request.replacement_request?
      send_text_acknowledgement(to: from, message: "❌ This is not a valid replacement request.")
      return
    end

    requestable = return_request.requestable
    dealer = find_dealer_by_phone(from)

    unless dealer && requestable.try(:seller_dealer_id) == dealer.id
      send_text_acknowledgement(to: from, message: "❌ You are not authorized to manage this replacement request.")
      return
    end

    begin
      case action
      when "accept"
        unless return_request.status == "requested"
          send_text_acknowledgement(to: from, message: "ℹ️ Replacement request is already #{return_request.status.humanize.downcase}.")
          return
        end

        ReturnRequestTransitionService.new(
          return_request: return_request,
          actor: dealer,
          resolution_notes: "Approved via WhatsApp"
        ).transition!(next_status: "approved")

        ReplacementRequestNotificationService.request_updated!(return_request.reload, actor: dealer)
        send_text_acknowledgement(to: from, message: "✅ Replacement request ##{return_request.id} approved! Click 'Mark Shipped' when dispatched.")

      when "reject"
        unless return_request.status == "requested"
          send_text_acknowledgement(to: from, message: "ℹ️ Replacement request is already #{return_request.status.humanize.downcase}.")
          return
        end

        ReturnRequestTransitionService.new(
          return_request: return_request,
          actor: dealer,
          resolution_notes: "Rejected via WhatsApp"
        ).transition!(next_status: "rejected")

        ReplacementRequestNotificationService.request_updated!(return_request.reload, actor: dealer)
        send_text_acknowledgement(to: from, message: "❌ Replacement request ##{return_request.id} rejected. Buyer has been notified.")

      when "ship"
        unless return_request.status == "approved"
          send_text_acknowledgement(to: from, message: "ℹ️ Replacement request must be approved before marking as shipped. Current status: #{return_request.status.humanize.downcase}.")
          return
        end

        updated_request = ReturnRequestTransitionService.new(
          return_request: return_request,
          actor: dealer,
          resolution_notes: "Marked as shipped via WhatsApp"
        ).transition!(next_status: "in_transit")

        DeliveryConfirmationService.new(deliverable: updated_request.requestable, actor: dealer)
          .create_replacement!(return_request: updated_request)

        ReplacementRequestNotificationService.request_shipped!(updated_request.reload, actor: dealer)
        send_text_acknowledgement(to: from, message: "📦 Replacement request ##{return_request.id} marked as shipped! Delivery verification link sent.")
      else
        send_text_acknowledgement(to: from, message: "❌ Unknown action.")
      end
    rescue StandardError => e
      send_text_acknowledgement(to: from, message: "❌ Failed to update replacement request: #{e.message}")
      Rails.logger.error("handle_replacement_response failed for request #{return_request_id}: #{e.message}")
    end
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

    order.reload
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

        offer = OrderOffer.find_by(whatsapp_message_id: message_id)

        if offer.nil?
          offer = B2bOrderOffer.find_by(whatsapp_message_id: message_id)
        end
        next unless offer

        # event.update!(b2b_order_offer: offer)
        case offer
        when OrderOffer
          event.update!(order_offer: offer)
        when B2bOrderOffer
          event.update!(b2b_order_offer: offer)
        end
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
    order = get_order_from_offer(offer)
    WhatsappWebhookEvent.create!(
      provider: "meta",
      event_type: "button_reply",
      event_key: "reply:#{SecureRandom.uuid}",
      direction: "inbound",
      # b2b_order_offer: offer,
      notification: offer.notification,
      from_number: from,
      status: action,
      processed_at: Time.current,
      payload: {
        button_id: offer.accept_token,
        from: from,
        action: action,
        dealer_id: offer.dealer&.id,
        order_type: order.is_a?(Order) ? "b2c" : (order.is_direct_buy? && order.source_type == "WholesalerPost" ? "wholesaler" : "b2b"),
        order_id: order.is_a?(Order) ? order.order_number : order.reference_number,
        offer_type: offer.class.name,
        is_wholesaler: order.is_a?(B2bOrder) && order.is_direct_buy? && order.source_type == "WholesalerPost"
      }
    )
  end

  def send_text_acknowledgement(to:, message:)
    MetaWhatsappCloudService.new.send_text_message(
      to: normalized_e164_from_wa_id(to),
      body: message
    )
  end

  def get_order_from_offer(offer)
    if offer.is_a?(OrderOffer)
      offer.order
    elsif offer.is_a?(B2bOrderOffer)
      offer.b2b_order
    else
      raise StandardError, "Unknown offer type"
    end
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

  # Find a dealer by their WhatsApp phone number (used in replacement flow)
  def find_dealer_by_phone(from)
    digits = from.to_s.gsub(/\D/, "")
    return nil if digits.blank?

    # Strip leading country code (try last 10 digits for India)
    phone_10 = digits.length >= 10 ? digits[-10..] : digits

    Dealer.find_each do |dealer|
      dealer_phone = dealer.phone.to_s.gsub(/\D/, "")
      next if dealer_phone.blank?

      dealer_10 = dealer_phone.length >= 10 ? dealer_phone[-10..] : dealer_phone
      return dealer if dealer_10 == phone_10
    end

    nil
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