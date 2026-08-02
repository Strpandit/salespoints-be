class ReplacementRequestNotificationService
  class << self
    def request_created!(return_request, actor:)
      new(return_request, actor: actor, event: :created).dispatch!
    end

    def request_updated!(return_request, actor:)
      new(return_request, actor: actor, event: :updated).dispatch!
    end
  end

  def initialize(return_request, actor:, event:)
    @return_request = return_request
    @actor = actor
    @event = event.to_sym
    @requestable = return_request.requestable
  end

  def dispatch!
    notify_buyer!
    notify_super_admins!
    notify_seller_on_create! if created_event?
    notify_seller_whatsapp_on_create! if created_event?
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
      event.to_s,
      changed_fields_payload
    ).deliver_later
  end

  def notify_seller_whatsapp_on_create!
    seller = seller_recipient
    return if seller.blank?

    to = normalized_whatsapp_number(seller)
    return if to.blank?

    MetaWhatsappCloudService.new.send_text_message(
      to: to,
      body: whatsapp_message
    )
  rescue StandardError => e
    Rails.logger.error("ReplacementRequestNotificationService WhatsApp failed for request #{return_request.id}: #{e.message}")
  end

  def buyer_recipient
    case requestable
    when Order
      requestable.buyer
    when B2bOrder
      requestable.buyer_dealer
    end
  end

  def seller_recipient
    requestable.try(:seller_dealer)
  end

  def super_admins
    AdminUser.active.select(&:super_admin?)
  end

  def created_event?
    event == :created
  end

  def email_subject_for(recipient_role)
    order_reference = request_reference_number
    status_label = return_request.status.to_s.humanize

    case recipient_role.to_s
    when "seller"
      "Replacement request raised for order #{order_reference}"
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
    if created_event?
      build_created_changes
    else
      build_updated_changes
    end
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

    recipient.try(:full_name).presence ||
      recipient.try(:first_name).presence ||
      recipient.try(:dealer_code).presence ||
      recipient.try(:email).presence ||
      fallback
  end

  def normalized_whatsapp_number(recipient)
    phone = recipient.try(:phone).to_s.gsub(/\D/, "")
    return nil if phone.blank?

    country_code = recipient.try(:country_code).to_s.gsub(/\D/, "")
    country_code = "91" if country_code.blank?
    "#{country_code}#{phone}"
  end

  def whatsapp_message
    details = [
      "Replacement request received on SalesPoints",
      "Order No: #{request_reference_number}",
      "Seller: #{seller_display_name}",
      "Request Status: #{return_request.status.to_s.humanize}",
      "Reason: #{return_request.reason.presence || 'NA'}",
      "Details: #{return_request.details.presence || 'NA'}",
      "Requested At: #{return_request.created_at.strftime('%d %b %Y, %I:%M %p')}"
    ]

    details.join("\n")
  end
end
