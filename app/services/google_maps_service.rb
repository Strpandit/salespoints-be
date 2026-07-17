class GoogleMapsService
  include Singleton

  def initialize
    @api_key = ENV['GOOGLE_MAPS_API_KEY']
  end

  # ✅ Geocode Address → Coordinates
  def geocode(address)
    return nil if address.blank?

    results = Geocoder.search(address)
    return nil if results.empty?

    result = results.first
    {
      latitude: result.latitude,
      longitude: result.longitude,
      formatted_address: result.formatted_address,
      postal_code: result.postal_code,
      city: result.city,
      state: result.state,
      country: result.country,
      address_components: result.address_components
    }
  end

  # ✅ Reverse Geocode → Address from Coordinates
  def reverse_geocode(lat, lng)
    return nil if lat.blank? || lng.blank?

    results = Geocoder.search([lat, lng])
    return nil if results.empty?

    result = results.first
    {
      formatted_address: result.formatted_address,
      postal_code: result.postal_code,
      city: result.city,
      state: result.state,
      country: result.country,
      address_components: result.address_components
    }
  end

  # ✅ Distance Matrix - Driving Distance between points
  def distance_matrix(origins, destinations)
    return nil if origins.blank? || destinations.blank?

    origins_str = origins.is_a?(Array) ? origins.map { |o| o.join(',') }.join('|') : origins.join(',')
    destinations_str = destinations.is_a?(Array) ? destinations.map { |d| d.join(',') }.join('|') : destinations.join(',')

    url = "https://maps.googleapis.com/maps/api/distancematrix/json?origins=#{origins_str}&destinations=#{destinations_str}&key=#{@api_key}"

    response = HTTParty.get(url)
    return nil unless response.success?

    JSON.parse(response.body)
  end

  # ✅ Driving distance between two coordinates
  def driving_distance(lat1, lng1, lat2, lng2)
    result = distance_matrix(
      [[lat1, lng1]],
      [[lat2, lng2]]
    )

    return nil if result.blank?
    return nil if result['status'] != 'OK'
    return nil if result['rows'].blank?
    return nil if result['rows'][0]['elements'].blank?

    element = result['rows'][0]['elements'][0]
    return nil if element['status'] != 'OK'

    {
      distance_km: element['distance']['value'].to_f / 1000.0,
      distance_text: element['distance']['text'],
      duration_min: element['duration']['value'].to_f / 60.0,
      duration_text: element['duration']['text']
    }
  end

  # ✅ Find nearby dealers within radius
  def nearby_dealers(lat, lng, radius_km: 10, limit: 20)
    dealers = Dealer.active
                    .includes(:dealer_location)
                    .where.not(dealer_locations: { latitude: nil, longitude: nil })
                    .limit(100)

    results = []

    dealers.each do |dealer|
      location = dealer.dealer_location
      next if location.blank?

      distance_info = driving_distance(
        lat.to_f,
        lng.to_f,
        location.latitude.to_f,
        location.longitude.to_f
      )

      next if distance_info.blank?
      next if distance_info[:distance_km] > radius_km.to_f

      results << {
        dealer: dealer,
        distance_km: distance_info[:distance_km].round(2),
        distance_text: distance_info[:distance_text],
        duration_min: distance_info[:duration_min].round(0),
        duration_text: distance_info[:duration_text]
      }
    end

    results.sort_by { |r| r[:distance_km] }.first(limit)
  end

  # ✅ Search places (autocomplete)
  def search_places(query)
    return [] if query.blank?

    url = "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=#{CGI.escape(query)}&key=#{@api_key}&components=country:IN"

    response = HTTParty.get(url)
    return [] unless response.success?

    data = JSON.parse(response.body)
    return [] if data['status'] != 'OK'

    data['predictions'].map do |prediction|
      {
        description: prediction['description'],
        place_id: prediction['place_id'],
        types: prediction['types']
      }
    end
  end

  # ✅ Get place details by place_id
  def place_details(place_id)
    return nil if place_id.blank?

    url = "https://maps.googleapis.com/maps/api/place/details/json?place_id=#{place_id}&key=#{@api_key}"

    response = HTTParty.get(url)
    return nil unless response.success?

    data = JSON.parse(response.body)
    return nil if data['status'] != 'OK'

    result = data['result']
    {
      formatted_address: result['formatted_address'],
      latitude: result['geometry']['location']['lat'],
      longitude: result['geometry']['location']['lng'],
      postal_code: result['address_components']&.find { |c| c['types'].include?('postal_code') }&.dig('short_name'),
      city: result['address_components']&.find { |c| c['types'].include?('locality') }&.dig('long_name'),
      state: result['address_components']&.find { |c| c['types'].include?('administrative_area_level_1') }&.dig('long_name')
    }
  end

  # ✅ Validate address
  def validate_address(address)
    result = geocode(address)
    return { valid: false, error: 'Address not found' } if result.blank?

    {
      valid: true,
      formatted_address: result[:formatted_address],
      postal_code: result[:postal_code],
      city: result[:city],
      state: result[:state],
      country: result[:country],
      latitude: result[:latitude],
      longitude: result[:longitude]
    }
  rescue => e
    { valid: false, error: e.message }
  end
end