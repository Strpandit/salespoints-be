class OrderItemSerializer < ApplicationSerializer
  attributes :quantity, :unit_price, :taxable_amount, :gst_percentage, 
            :gst_amount, :total_price, :product_name, :product_name_with_variant,
            :variant_sku, :product_id, :variant_id, :product_media, :variant_media,
            :color, :image_url

  def image_url
    file = object.product_variant&.media&.first || object.product_variant&.product&.media&.first
    return nil unless file
    file_payload(file)[:url]
  end

  def pricing
    @pricing ||= Pricing::PriceCalculator.new(
      variant: object.product_variant,
      quantity: object.quantity,
      user_type: object.order.buyer_type == "Dealer" ? :dealer : :account
    ).call
  end

  def unit_price
    pricing[:unit_price]
  end

  def taxable_amount
    pricing[:taxable_amount]
  end

  def gst_percentage
    pricing[:gst_percentage]
  end

  def gst_amount
    pricing[:gst_amount]
  end

  def total_price
    pricing[:total]
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

  def product_id
    object.product_variant&.product_id
  end

  def variant_id
    object.product_variant_id
  end

  def product_media
    object.product_variant&.product.media.map { |file| file_payload(file) }
  end

  def variant_media
    object.product_variant.media.map { |file| file_payload(file) }
  end

  def color
    if object.product_variant_color.present?
      object.product_variant_color.color_name
    elsif object.ad_hoc_color.present?
      object.ad_hoc_color
    else
      "Standard"
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
