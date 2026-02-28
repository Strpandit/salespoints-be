class DealerLocation < ApplicationRecord
  belongs_to :dealer

  validates :latitude, :longitude, presence: true
  validates :service_radius_km, numericality: { greater_than: 0 }
end
