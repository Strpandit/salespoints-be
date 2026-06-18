class ProductVariantSerializer < ApplicationSerializer
  attributes :product_id, :variant_sku, :price, :selling_price, :dealer_price, :dealer_selling_price, 
             :discount_percentage, :is_active, :formatted_variant_attributes, :deleted_at, :media, :tax_rate, :tax_inclusive

  def price
    object.inclusive_price.to_f
  end

  def selling_price
    object.inclusive_selling_price.to_f
  end

  def dealer_price
    object.inclusive_dealer_price.to_f
  end

  def dealer_selling_price
    object.inclusive_dealer_selling_price.to_f
  end

  def media
    object.display_media_attachments.map { |file| file_payload(file) }
  end

  def tax_rate
    object.product.tax_rate.to_f
  end

  def tax_inclusive
    true
  end

  def formatted_variant_attributes
    attrs = object.variant_attributes

    return [] if attrs.blank?

    if attrs.is_a?(Array)
      attrs
    elsif attrs.is_a?(Hash)
      attrs.map do |k, v|
        { key: k, value: v }
      end
    elsif attrs.is_a?(String)
      begin
        parsed = JSON.parse(attrs)

        if parsed.is_a?(Array)
          parsed
        elsif parsed.is_a?(Hash)
          parsed.map do |k, v|
            { key: k, value: v }
          end
        else
          []
        end
      rescue
        []
      end
    else
      []
    end
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
