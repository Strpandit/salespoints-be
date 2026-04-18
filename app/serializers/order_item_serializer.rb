class OrderItemSerializer < ApplicationSerializer
  attributes :quantity, :unit_price, :total_price, :product_name, :product_name_with_variant, :variant_sku

  def unit_price
    object.unit_price
  end

  def total_price
    object.total_price
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
end
