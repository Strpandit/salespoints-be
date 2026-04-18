class B2bOrderItemSerializer < ApplicationSerializer
  attributes :dealer_product_id, :product_variant_id, :quantity, :status, :responded_at,
             :unit_price, :total_price, :product_name, :variant_sku, :assigned_dealer_name

  def unit_price
    object.unit_price.to_f
  end

  def total_price
    object.total_price.to_f
  end

  def product_name
    object.product_variant&.product&.name
  end

  def variant_sku
    object.product_variant&.variant_sku
  end

  def assigned_dealer_name
    object.dealer_product&.dealer&.dealer_code
  end
end
