class DealerProductSerializer < ApplicationSerializer

  attributes :stock_quantity, :is_active, :approve_status, :created_at, :updated_at, :distance_km

  belongs_to :dealer
  belongs_to :product
  belongs_to :product_variant

  def distance_km
    object.respond_to?(:distance_km) ? object.distance_km : nil
  end
end
