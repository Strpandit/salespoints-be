class CartSerializer < ActiveModel::Serializer
  attributes :id, :total_amount
  has_many :cart_items
end