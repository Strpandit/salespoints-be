class CartItemSerializer < ApplicationSerializer
  attributes :quantity, :cart_id, :dealer_product_id, :product_variant_id, :unit_price, :taxable_amount, 
             :gst_percentage, :gst_amount, :total_price, :media, :product_media, :variant_media

  belongs_to :dealer_product
  belongs_to :product_variant

  def pricing
    @pricing ||= Pricing::PriceCalculator.new(
      variant: object.product_variant,
      quantity: object.quantity,
      user_type: object.cart.dealer? ? :dealer : :account
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
