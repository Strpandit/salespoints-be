class B2bOrderItemSerializer < ApplicationSerializer
  attributes :dealer_product_id, :product_variant_id, :quantity, :status, :responded_at,
             :unit_price, :taxable_amount, :gst_percentage, :gst_amount, :total_price, :product_name, :variant_sku, :assigned_dealer_name,
             :media, :product_media, :variant_media

  def pricing
    if object.product_variant.present?
      @pricing ||= Pricing::PriceCalculator.new(
        variant: object.product_variant,
        quantity: object.quantity,
        user_type: :dealer
      ).call
    else
      {
        unit_price: object.unit_price.to_f,
        taxable_amount: object.unit_price.to_f * object.quantity,
        gst_percentage: 18.0,
        gst_amount: 0,
        total: object.total_price.to_f
      }
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
    return object.wholesaler_post&.title if object.wholesaler_post_id.present?

    return object.product_variant&.product&.name if object.product_variant_id.present?

    return object.dealer_product&.product&.name if object.dealer_product_id.present?
  end

  def variant_sku
    return object.wholesaler_post&.modal_no if object.wholesaler_post_id.present?
    
    return object.product_variant&.variant_sku if object.product_variant_id.present?
    
    nil
  end

  def assigned_dealer_name
    return object.dealer_product&.dealer&.dealer_code if object.dealer_product_id.present?

    return object.wholesaler_post&.dealer&.dealer_code if object.wholesaler_post_id.present?
    
    nil
  end

  def media
    if object.wholesaler_post_id.present?
      return object.wholesaler_post&.media&.map { |file| file_payload(file) } || []
    end

    return [] unless object.dealer_product

    object.dealer_product.display_media_attachments.map { |file| file_payload(file) }
  end

  def product_media
    if object.wholesaler_post_id.present?
      return object.wholesaler_post&.media&.map { |file| file_payload(file) } || []
    end

    return [] unless object.product_variant_id.present?
    object.product_variant&.product&.media&.map { |file| file_payload(file) } || []
  end

  def variant_media
    if object.wholesaler_post_id.present?
      return object.wholesaler_post&.media&.map { |file| file_payload(file) } || []
    end
    
    return [] unless object.product_variant_id.present?
    object.product_variant&.media&.map { |file| file_payload(file) } || []
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
