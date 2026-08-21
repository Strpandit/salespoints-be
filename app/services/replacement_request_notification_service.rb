class ReplacementRequestNotificationService
  TOKEN_SALT = "replacement_request_tokens".freeze
  TOKEN_EXPIRY = 2.days

  class << self
    def request_created!(return_request, actor:)
      new(return_request, actor: actor, event: :created).dispatch!
    end

    def request_updated!(return_request, actor:)
      new(return_request, actor: actor, event: :updated).dispatch!
    end

    def request_shipped!(return_request, actor:)
      new(return_request, actor: actor, event: :shipped).dispatch!
    end

    def request_completed!(return_request, actor:)
      new(return_request, actor: actor, event: :completed).dispatch!
    end

    def accept_token_for(return_request)
      generate_compact_token("accept", return_request.id)
    end

    def reject_token_for(return_request)
      generate_compact_token("reject", return_request.id)
    end

    def shipped_token_for(return_request)
      generate_compact_token("ship", return_request.id)
    end

    def generate_compact_token(action, id)
      exp = (Time.now + TOKEN_EXPIRY).to_i
      payload = "#{action}:#{id}:#{exp}"
      sig = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, payload)[0..15]
      "#{payload}:#{sig}"
    end

    def decode_token(token)
      return nil if token.blank?

      if token.start_with?("ey") || token.include?("--")
        purpose = token_purpose(token)
        return nil if purpose.nil?

        payload = verifier.verified(token, purpose: purpose) rescue nil
        return nil if payload.nil?

        return { action: payload[:action], id: payload[:id] }
      end

      parts = token.split(":")
      return nil unless parts.length == 4

      action, id_str, exp_str, sig = parts
      exp = exp_str.to_i
      return nil if Time.now.to_i > exp

      payload = "#{action}:#{id_str}:#{exp_str}"
      expected_sig = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, payload)[0..15]

      return nil unless ActiveSupport::SecurityUtils.secure_compare(sig, expected_sig)

      { action: action, id: id_str.to_i }
    rescue StandardError
      nil
    end

    private

    def verifier
      ActiveSupport::MessageVerifier.new(
        Rails.application.secret_key_base,
        digest: "SHA256",
        serializer: JSON
      )
    end

    def token_purpose(token)
      ["replacement_accept", "replacement_reject", "replacement_ship"].find do |purpose|
        verifier.verified(token, purpose: purpose) rescue nil
      end
    end
  end

  def initialize(return_request, actor:, event:)
    @return_request = return_request
    @actor = actor
    @event = event.to_sym
    @requestable = return_request.requestable
  end

  def dispatch!
    case @event
    when :created
      notify_buyer!
      notify_super_admins!
      notify_seller_on_create!
      notify_seller_whatsapp_with_buttons!
    when :updated
      notify_buyer!
      notify_super_admins!
      notify_seller_on_update!
      if return_request.status == "approved"
        notify_seller_whatsapp_approved_with_shipped_button!
      end
    when :shipped
      notify_buyer!
      notify_super_admins!
      notify_seller_on_update!
    when :completed
      notify_buyer!
      notify_super_admins!
      notify_seller_on_update!
    end
  end

  private

  attr_reader :return_request, :actor, :event, :requestable

  def notify_buyer!
    buyer = buyer_recipient
    return if buyer.blank?
    changes = changed_fields_payload

    NotificationService.deliver(
      recipient: buyer,
      actor: actor,
      notifiable: return_request,
      kind: notification_kind_for("buyer"),
      title: email_subject_for("buyer"),
      message: in_app_message_for("buyer"),
      payload: notification_payload(changes).merge("recipient_role" => "buyer"),
      delivery_channels: { push: true, email: true, in_app: true }
    )

    return if buyer.email.blank?

    ReplacementRequestMailer.lifecycle_update(
      return_request.id,
      buyer.email,
      "buyer",
      event.to_s,
      changes
    ).deliver_later
  end

  def notify_super_admins!
    changes = changed_fields_payload

    super_admins.each do |admin|
      NotificationService.deliver(
        recipient: admin,
        actor: actor,
        notifiable: return_request,
        kind: notification_kind_for("super_admin"),
        title: email_subject_for("super_admin"),
        message: in_app_message_for("super_admin"),
        payload: notification_payload(changes).merge("recipient_role" => "super_admin"),
        delivery_channels: { push: true, email: true, in_app: true }
      )

      next if admin.email.blank?

      ReplacementRequestMailer.lifecycle_update(
        return_request.id,
        admin.email,
        "super_admin",
        event.to_s,
        changes
      ).deliver_later
    end
  end

  def notify_seller_on_create!
    seller = seller_recipient
    return if seller.blank? || seller.email.blank?

    ReplacementRequestMailer.lifecycle_update(
      return_request.id,
      seller.email,
      "seller",
      "created",
      changed_fields_payload
    ).deliver_later
  end

  def notify_seller_on_update!
    seller = seller_recipient
    return if seller.blank? || seller.email.blank?

    ReplacementRequestMailer.lifecycle_update(
      return_request.id,
      seller.email,
      "seller",
      event.to_s,
      changed_fields_payload
    ).deliver_later
  end

  def notify_seller_whatsapp_with_buttons!
    seller = seller_recipient
    return if seller.blank?

    to = normalized_whatsapp_number(seller)
    return if to.blank?

    accept_tok = self.class.accept_token_for(return_request)
    reject_tok = self.class.reject_token_for(return_request)

    MetaWhatsappCloudService.new.send_replacement_request(
      to: to,
      order_ref: request_reference_number,
      buyer_name: buyer_display_name,
      items_summary: items_summary,
      total_amount: "₹#{requestable.total_amount.to_f.round(2)}",
      address: shipping_address_text,
      reason: return_request.reason.presence || "Not specified",
      accept_token: accept_tok,
      reject_token: reject_tok
    )
  rescue StandardError => e
    Rails.logger.error("ReplacementRequestNotificationService WhatsApp (create) failed for #{return_request.id}: #{e.message}")
  end

  def notify_seller_whatsapp_approved_with_shipped_button!
    seller = seller_recipient
    return if seller.blank?

    to = normalized_whatsapp_number(seller)
    return if to.blank?

    shipped_tok = self.class.shipped_token_for(return_request)
    buyer = buyer_recipient

    buyer_phone = buyer.try(:phone).presence || requestable.try(:shipping_address)&.dig("phone") || "N/A"
    latitude, longitude, location_name = get_buyer_location_details

    MetaWhatsappCloudService.new.send_order_accept(
      to: to,
      dealer_code: buyer_display_name,
      phone: buyer_phone,
      address: shipping_address_text,
      order_id: request_reference_number,
      payment_mode: requestable.try(:payment_method).to_s.upcase.presence || "COD",
      total_amount: "₹#{requestable.try(:total_amount).to_f.round(2)}",
      latitude: latitude,
      longitude: longitude,
      location_name: location_name,
      shipped_token: shipped_tok
    )
  rescue StandardError => e
    Rails.logger.error("ReplacementRequestNotificationService WhatsApp (approved) failed for #{return_request.id}: #{e.message}")
  end

  def get_buyer_location_details
    loc_name = if requestable.is_a?(B2bOrder)
                 "Salespoints Dealer Point #{buyer_display_name}"
               else
                 buyer_display_name
               end

    addr_text = shipping_address_text
    if addr_text.present? && addr_text != "Address not available"
      results = Geocoder.search(addr_text) rescue []
      if results.any? && results.first.latitude.present? && results.first.longitude.present?
        return [results.first.latitude.to_f, results.first.longitude.to_f, loc_name]
      end
    end

    [28.6139, 77.2090, loc_name]
  end

  def buyer_recipient
    case requestable
    when Order   then requestable.buyer
    when B2bOrder then requestable.buyer_dealer
    end
  end

  def seller_recipient
    requestable.try(:seller_dealer)
  end

  def super_admins
    AdminUser.active.select(&:super_admin?)
  end

  def email_subject_for(recipient_role)
    order_reference = request_reference_number
    status_label = return_request.status.to_s.humanize

    case recipient_role.to_s
    when "seller"
      created_event? ? "Replacement request raised for order #{order_reference}" : "Replacement request #{status_label} for order #{order_reference}"
    when "super_admin"
      created_event? ? "New replacement request for order #{order_reference}" : "Replacement request #{status_label} for order #{order_reference}"
    else
      created_event? ? "Your replacement request has been submitted for order #{order_reference}" : "Your replacement request for order #{order_reference} is now #{status_label}"
    end
  end

  def in_app_message_for(recipient_role)
    actor_name = actor_display_name
    status_label = return_request.status.to_s.humanize.downcase
    order_reference = request_reference_number

    case recipient_role.to_s
    when "super_admin"
      if created_event?
        "#{actor_name} raised a replacement request for order #{order_reference}."
      else
        "Replacement request for order #{order_reference} is now #{status_label}."
      end
    else
      if created_event?
        "Replacement request submitted for order #{order_reference}."
      else
        "Replacement request for order #{order_reference} is now #{status_label}."
      end
    end
  end

  def notification_kind_for(recipient_role)
    prefix = recipient_role.to_s == "super_admin" ? "admin" : recipient_role.to_s
    suffix = created_event? ? "created" : "updated"
    "#{prefix}_replacement_request_#{suffix}"
  end

  def notification_payload(changes = changed_fields_payload)
    {
      replacement_request_id: return_request.id,
      request_type: return_request.request_type,
      status: return_request.status,
      requestable_type: requestable.class.name,
      requestable_id: requestable.id,
      order_number: request_reference_number,
      buyer_name: buyer_display_name,
      seller_name: seller_display_name,
      changed_fields: changes,
      reason: return_request.reason,
      details: return_request.details,
      resolution_notes: return_request.resolution_notes
    }.compact
  end

  def changed_fields_payload
    tracked_changes.map do |field|
      {
        field: field[:field],
        label: field[:label],
        before: field[:before],
        after: field[:after]
      }.compact
    end
  end

  def tracked_changes
    created_event? ? build_created_changes : build_updated_changes
  end

  def build_created_changes
    fields = []
    append_change(fields, "status", nil, return_request.status)
    append_change(fields, "reason", nil, return_request.reason)
    append_change(fields, "details", nil, return_request.details)
    append_change(fields, "request_type", nil, return_request.request_type)
    fields
  end

  def build_updated_changes
    fields = []

    previous = return_request.previous_changes.stringify_keys
    %w[status resolution_notes approved_at shipped_at received_at completed_at rejected_at cancelled_at].each do |field|
      before_after = previous[field]
      next if before_after.blank?

      append_change(fields, field, before_after[0], before_after[1])
    end

    fields.presence || [fallback_status_change]
  end

  def fallback_status_change
    {
      field: "status",
      label: "Status",
      after: return_request.status.to_s.humanize
    }
  end

  def append_change(collection, field, before_value, after_value)
    after_text = humanize_change_value(field, after_value)
    before_text = humanize_change_value(field, before_value)
    return if before_text == after_text

    collection << {
      field: field,
      label: field.to_s.humanize,
      before: before_text,
      after: after_text
    }.compact
  end

  def humanize_change_value(field, value)
    return nil if value.blank?

    case field.to_s
    when /_at\z/
      value.respond_to?(:strftime) ? value.strftime("%d %b %Y, %I:%M %p") : value.to_s
    when "status", "request_type"
      value.to_s.humanize
    else
      value.to_s
    end
  end

  def request_reference_number
    requestable.try(:order_number).presence || requestable.try(:reference_number).presence || "##{requestable.id}"
  end

  def buyer_display_name
    recipient_name(buyer_recipient, fallback: "Buyer")
  end

  def seller_display_name
    recipient_name(seller_recipient, fallback: "Seller")
  end

  def actor_display_name
    recipient_name(actor, fallback: "A user")
  end

  def recipient_name(recipient, fallback:)
    return fallback if recipient.blank?

    recipient.try(:dealer_code).presence ||
    recipient.try(:full_name).presence ||
    recipient.try(:first_name).presence ||
    recipient.try(:email).presence ||
    fallback
  end

  def created_event?
    @event == :created
  end

  def items_summary
    items = case requestable
            when Order    then requestable.order_items
            when B2bOrder then requestable.b2b_order_items
            else []
            end

    return "N/A" if items.blank?

    lines = items.map do |item|
      name = item.try(:product_name_with_variant) ||
             item.try(:product_variant)&.product&.name ||
             item.try(:wholesaler_post)&.title ||
             "Product"
      qty  = item.quantity.to_i
      "#{name} x#{qty}"
    end

    lines.join(", ").truncate(200)
  end

  def shipping_address_text
    addr = requestable.try(:shipping_address)

    if addr.is_a?(Hash) && addr.present?
      parts = [
        addr["address_line1"],
        addr["address_line2"],
        addr["city"],
        addr["state"],
        addr["postal_code"]
      ].compact.reject(&:blank?)
      return parts.join(", ") if parts.any?
    elsif addr.is_a?(String) && addr.present?
      return addr
    end

    buyer = buyer_recipient
    if buyer.respond_to?(:dealer_profile) && buyer.dealer_profile&.business_address.present?
      return buyer.dealer_profile.business_address
    end

    "Address not available"
  end

  def normalized_whatsapp_number(recipient)
    phone = recipient.try(:phone).to_s.gsub(/\D/, "")
    return nil if phone.blank?

    country_code = recipient.try(:country_code).to_s.gsub(/\D/, "")
    country_code = "91" if country_code.blank?
    "#{country_code}#{phone}"
  end
end
