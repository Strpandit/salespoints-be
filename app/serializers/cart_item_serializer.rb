class CartItemSerializer < ApplicationSerializer
  attributes :quantity, :cart_id, :dealer_product_id, :product_variant_id, :unit_price, :total_price

  belongs_to :dealer_product
  belongs_to :product_variant

  def unit_price
    object.unit_price.to_f
  end

  def total_price
    object.total_price.to_f
  end
end
