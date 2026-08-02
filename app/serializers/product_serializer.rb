class ProductSerializer < ApplicationSerializer
  include MediaPayloadBuilder
  attributes :name, :slug, :sku, :desc, :material, :features, :care_instructions,
             :is_featured, :is_new, :is_active, :tax_rate, :deleted_at, :specifications, 
             :media, :price, :selling_price, :dealer_price, :dealer_selling_price, :discount_percentage,
             :price_source, :tax_inclusive, :hsn_code, :desc_blocks

  belongs_to :category
  belongs_to :brand
  has_many :product_variants

  def specifications
    object.product_specifications.each_with_object({}) do |spec, hash|
      hash[spec.key] = spec.value
    end
  end

  def media
    blobs = object.ordered_media_attachments.map(&:blob)
    build_media_payloads(blobs, primary_blob_id: object.primary_media_blob_id)
  end

  def tax_inclusive
    true
  end

  def desc_blocks
    FormattedTextParser.parse(object.desc)
  end

end
