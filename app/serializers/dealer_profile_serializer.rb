class DealerProfileSerializer < ApplicationSerializer
  attributes :business_name, :business_type, :gst_number, :pan_number,
             :aadhar_number, :bank_name, :bank_account_number, :ifsc_code,
             :business_address, :business_contact_number, :business_email,
             :work_category, :associated_brands, :store_image, :aadhar_card, :pan_card, 
             :gst_certificate, :is_verified, :created_at, :updated_at

  def store_image
    object.store_image.map { |file| file_payload(file) }
  end

  def aadhar_card
    return nil unless object.aadhar_card.attached?

    file_payload(object.aadhar_card)
  end

  def pan_card
    return nil unless object.pan_card.attached?

    file_payload(object.pan_card)
  end

  def gst_certificate
    return nil unless object.gst_certificate.attached?

    file_payload(object.gst_certificate)
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
