class DealerLocation < ApplicationRecord
  belongs_to :dealer

  validates :latitude, :longitude, presence: true
  validates :service_radius_km, numericality: { greater_than: 0 }

  def self.distance_km(lat1, lon1, lat2, lon2)
    r = 6371.0
    dlat = to_rad(lat2.to_f - lat1.to_f)
    dlon = to_rad(lon2.to_f - lon1.to_f)
    a = Math.sin(dlat / 2)**2 +
        Math.cos(to_rad(lat1)) * Math.cos(to_rad(lat2)) * Math.sin(dlon / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    r * c
  end

  def self.to_rad(deg)
    deg.to_f * Math::PI / 180.0
  end
end
