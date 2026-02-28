class DealerProductSerializer < ActiveModel::Serializer
  attributes :id, :stock_quantity, :is_active, :approve_status, :created_at, :updated_at

  belongs_to :dealer
  belongs_to :product
  belongs_to :product_variant
end
