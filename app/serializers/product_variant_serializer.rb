class ProductVariantSerializer < ApplicationSerializer
  attributes :product_id, :variant_sku, :price, :selling_price, :dealer_price,
             :dealer_selling_price, :discount_percentage, :is_active, :variant_attributes, :deleted_at
end
