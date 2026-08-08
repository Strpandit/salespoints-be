class ProductVariantSerializer < ApplicationSerializer
  include MediaPayloadBuilder
  attributes :product_id, :variant_sku, :price, :selling_price, :dealer_price, :dealer_selling_price, :consumer_discount_percentage,
             :dealer_discount_percentage, :is_active, :formatted_variant_attributes, :deleted_at, :media, :own_media, :tax_rate, :tax_inclusive, :hsn_code, :colors

  def media
    build_media_payloads(object.display_media_attachments, primary_blob_id: object.display_primary_blob_id)
  end

  def own_media
    build_media_payloads(object.ordered_media_attachments.map(&:blob), primary_blob_id: object.primary_media_blob_id)
  end

  def price
    object.price.to_f
  end

  def selling_price
    object.selling_price.to_f
  end

  def dealer_price
    object.dealer_price.to_f
  end

  def dealer_selling_price
    object.dealer_selling_price.to_f
  end

  def consumer_discount_percentage
    object.calculate_discount_percentage(:account)
  end

  def dealer_discount_percentage
    object.calculate_discount_percentage(:dealer)
  end

  def tax_rate
    object.product.tax_rate.to_f
  end

  def tax_inclusive
    true
  end

  def colors
    object.product_variant_colors.map do |c|
      {
        id: c.id,
        color_name: c.color_name,
        color_hex: c.color_hex
      }
    end
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
end
