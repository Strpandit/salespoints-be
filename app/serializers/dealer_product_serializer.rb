class DealerProductSerializer < ApplicationSerializer
  attributes :stock_quantity, :is_active, :approve_status, :sell_in_b2b, :sell_in_b2c, :created_at, :updated_at, :distance_km,
             :media, :consumer_discount_percentage,
             :dealer_discount_percentage

  belongs_to :dealer
  belongs_to :product
  belongs_to :product_variant

  def distance_km
    object.respond_to?(:distance_km) ? object.distance_km : nil
  end

  def consumer_discount_percentage
    object.product_variant&.calculate_discount_percentage(:account)
  end

  def dealer_discount_percentage
    object.product_variant&.calculate_discount_percentage(:dealer)
  end
  
  def media
    object.display_media_attachments.map { |file| file_payload(file) }
  end

  private

  def file_payload(file)
    host = options[:base_url] || Rails.application.config.active_storage.default_url_options&.dig(:host)
    {
      id: file.id,
      url: Rails.application.routes.url_helpers.rails_blob_url(file, host: host),
      filename: file.filename.to_s,
      content_type: file.content_type.to_s,
      is_primary: object.display_primary_blob_id == file.id
    }
  end
end
