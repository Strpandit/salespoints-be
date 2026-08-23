class DeliveryConfirmationSerializer < ApplicationSerializer
  attributes :token, :status, :notes, :seller_phone, :buyer_phone, :submitted_at, :completed_at,
             :buyer_otp_sent_at, :buyer_otp_verified,
             :invoice_reference_time, :buyer_name, :seller_name, :declarations, :uploads, :serial_numbers

  def buyer_otp_verified
    object.buyer_verified?
  end

  def uploads
    {
      product_with_customer_image: attachment_payload(object.product_with_customer_image),
      product_packaging_image: attachment_payload(object.product_packaging_image),
      product_open_box_images: object.product_open_box_images.map { |file| attachment_payload(file) }.compact
    }
  end

  private

  def attachment_payload(file)
    return nil if file.blank?

    if file.respond_to?(:attached?)
      return nil unless file.attached?
      file = file.attachment
    end

    blob = file.respond_to?(:blob) ? file.blob : file
    return nil if blob.blank? || !blob.respond_to?(:filename)

    {
      filename: blob.filename.to_s,
      content_type: blob.content_type,
      byte_size: blob.byte_size,
      url: Rails.application.routes.url_helpers.rails_blob_url(blob, only_path: false)
    }
  rescue StandardError
    nil
  end
end
