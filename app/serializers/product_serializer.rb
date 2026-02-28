class ProductSerializer < ActiveModel::Serializer
  attributes :id, :name, :slug, :sku, :desc, :material, :features, :care_instructions,
             :is_featured, :is_new, :is_active, :tax_rate, :deleted_at, :specifications

  belongs_to :category
  belongs_to :brand
  has_many :product_variants, serializer: ProductVariantSerializer

  def specifications
    object.product_specifications.each_with_object({}) do |spec, hash|
      hash[spec.key] = spec.value
    end
  end
end
