class DealerLocation < ApplicationRecord
  belongs_to :dealer

  validates :latitude, :longitude, presence: true
  validates :service_radius_km, numericality: { greater_than: 0 }

  def self.distance_km(lat1, lng1, lat2, lng2)
    Geocoder::Calculations.distance_between(
      [lat1, lng1],
      [lat2, lng2],
      units: :km
    )
  end

  def driving_distance_to(lat, lng)
    return nil if latitude.blank? || longitude.blank?

    service = GoogleMapsService.instance
    service.driving_distance(
      latitude.to_f,
      longitude.to_f,
      lat.to_f,
      lng.to_f
    )
  end

  def serves_location?(lat, lng)
    return false if latitude.blank? || longitude.blank?
    return false if service_radius_km.blank? || service_radius_km <= 0

    distance_info = driving_distance_to(lat, lng)
    return false if distance_info.blank?

    distance_info[:distance_km] <= service_radius_km.to_f
  end

  def self.nearby_dealers(lat, lng, radius_km: 10, limit: 20)
    service = GoogleMapsService.instance
    service.nearby_dealers(lat, lng, radius_km: radius_km, limit: limit)
  end

  def update_from_address(address)
    return false if address.blank?

    service = GoogleMapsService.instance
    result = service.geocode(address)
    return false if result.blank?

    update!(
      latitude: result[:latitude],
      longitude: result[:longitude]
    )
    true
  end
end
