class ReplacementRequestMailer < ApplicationMailer
  def lifecycle_update(return_request_id, recipient_email, recipient_role, event_name, changed_fields = nil)
    @return_request = ReturnRequest.find(return_request_id)
    @requestable = @return_request.requestable
    @recipient_role = recipient_role.to_s
    @event_name = event_name.to_s
    @buyer = buyer_recipient
    @seller = @requestable.try(:seller_dealer)
    @order_reference = @requestable.try(:order_number).presence || @requestable.try(:reference_number).presence || "##{@requestable.id}"
    @status_label = @return_request.status.to_s.humanize
    @changed_fields = normalize_changed_fields(changed_fields).presence || build_changed_fields

    mail(to: recipient_email, subject: subject_for(@recipient_role, @event_name))
  end

  private

  def buyer_recipient
    case @requestable
    when Order
      @requestable.buyer
    when B2bOrder
      @requestable.buyer_dealer
    end
  end

  def subject_for(recipient_role, event_name)
    case recipient_role.to_s
    when "seller"
      "Replacement request raised for order #{@order_reference}"
    when "super_admin"
      event_name == "created" ? "New replacement request for order #{@order_reference}" : "Replacement request #{@status_label} for order #{@order_reference}"
    else
      event_name == "created" ? "Your replacement request has been submitted for order #{@order_reference}" : "Your replacement request for order #{@order_reference} is now #{@status_label}"
    end
  end

  def build_changed_fields
    if @event_name == "created"
      [
        change_hash("Request Type", nil, @return_request.request_type.to_s.humanize),
        change_hash("Status", nil, @status_label),
        change_hash("Reason", nil, @return_request.reason),
        change_hash("Details", nil, @return_request.details)
      ].compact
    else
      tracked = @return_request.previous_changes.stringify_keys
      rows = []

      %w[status resolution_notes approved_at shipped_at received_at completed_at rejected_at cancelled_at].each do |field|
        next unless tracked[field].present?

        rows << change_hash(
          field.to_s.humanize,
          format_change_value(field, tracked[field][0]),
          format_change_value(field, tracked[field][1])
        )
      end

      rows.compact.presence || [change_hash("Status", nil, @status_label)]
    end
  end

  def normalize_changed_fields(changed_fields)
    Array(changed_fields).map do |row|
      next unless row.respond_to?(:to_h)

      item = row.to_h.stringify_keys
      next if item["after"].blank?

      {
        label: item["label"] || item["field"].to_s.humanize,
        before: item["before"],
        after: item["after"]
      }.compact
    end.compact
  end

  def change_hash(label, before_value, after_value)
    return nil if before_value == after_value || after_value.blank?

    {
      label: label,
      before: before_value,
      after: after_value
    }.compact
  end

  def format_change_value(field, value)
    return nil if value.blank?

    case field.to_s
    when /_at\z/
      format_date(value)
    when "status"
      value.to_s.humanize
    else
      value.to_s
    end
  end
end
