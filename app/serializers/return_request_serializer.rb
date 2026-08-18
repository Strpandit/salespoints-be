class ReturnRequestSerializer < ApplicationSerializer
  attributes :request_type, :status, :reason, :details, :refund_amount, :seller_adjustment_amount,
             :resolution_notes, :approved_at, :shipped_at, :received_at, :completed_at, :rejected_at, :cancelled_at,
             :replacement_mode, :defective_quantity, :defective_serial_numbers, :replacement_serial_numbers,
             :created_at, :updated_at, :requester_name, :media

  def refund_amount
    object.refund_amount.to_f
  end

  def seller_adjustment_amount
    object.seller_adjustment_amount.to_f
  end

  def defective_quantity
    object.defective_quantity.to_i
  end

  def defective_serial_numbers
    Array(object.defective_serial_numbers).reject(&:blank?)
  end

  def replacement_serial_numbers
    Array(object.replacement_serial_numbers).reject(&:blank?)
  end

  def requester_name
    if object.requester.respond_to?(:full_name)
      object.requester.full_name
    else
      object.requester.try(:first_name).presence || object.requester.try(:email) || object.requester_type
    end
  end

  def media
    object.media.map { |file| file_payload(file) }
  end

  private

  def file_payload(file)
    host = options[:base_url] || Rails.application.config.active_storage.default_url_options&.dig(:host)
    {
      id: file.id,
      url: Rails.application.routes.url_helpers.rails_blob_url(file, host: host),
      filename: file.filename.to_s,
      content_type: file.content_type.to_s
    }
  end
end
