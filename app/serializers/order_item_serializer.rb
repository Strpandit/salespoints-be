class OrderItemSerializer < ApplicationSerializer
  attributes :quantity, :unit_price, :total_price, :product_name, :product_name_with_variant, :variant_sku,
             :media, :product_media, :variant_media

  def unit_price
    object.unit_price.to_f
  end

  def total_price
    object.total_price.to_f
  end

  def product_name
    object.product_name
  end

  def product_name_with_variant
    object.product_name_with_variant
  end

  def variant_sku
    object.product_variant&.variant_sku
  end

  def media
    object.dealer_product.display_media_attachments.map { |file| file_payload(file) }
  end

  def product_media
    object.dealer_product.product.media.map { |file| file_payload(file) }
  end

  def variant_media
    object.product_variant.media.map { |file| file_payload(file) }
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
