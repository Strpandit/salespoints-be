class ProductSerializer < ApplicationSerializer
  attributes :name, :slug, :sku, :desc, :material, :features, :care_instructions,
             :is_featured, :is_new, :is_active, :tax_rate, :deleted_at, :specifications, 
             :media, :price, :selling_price, :dealer_price, :dealer_selling_price, :discount_percentage,
             :price_source

  belongs_to :category
  belongs_to :brand
  has_many :product_variants

  def price
    object.best_price
  end

  def selling_price
    object.best_selling_price
  end

  def dealer_price
    object.best_dealer_price
  end

  def dealer_selling_price
    object.best_dealer_selling_price
  end

  def discount_percentage
    object.best_discount_percentage
  end

  def price_source
    object.price_source
  end

  def specifications
    object.product_specifications.each_with_object({}) do |spec, hash|
      hash[spec.key] = spec.value
    end
  end

  def media
    object.media.map { |file| file_payload(file) }
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
