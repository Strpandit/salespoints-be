class ProductSerializer < ApplicationSerializer
  attributes :name, :slug, :sku, :desc, :material, :features, :care_instructions,
             :is_featured, :is_new, :is_active, :tax_rate, :deleted_at, :specifications, :media

  belongs_to :category
  belongs_to :brand
  has_many :product_variants

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
