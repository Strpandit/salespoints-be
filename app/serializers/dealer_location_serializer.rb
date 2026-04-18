class DealerLocationSerializer < ApplicationSerializer
  attributes :latitude, :longitude, :service_radius_km, :is_active
end
