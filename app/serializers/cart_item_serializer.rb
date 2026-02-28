class CartItemSerializer < ActiveModel::Serializer
  attributes :id, :dealer_product_id, :quantity, :total_price
  belongs_to :dealer_product
end