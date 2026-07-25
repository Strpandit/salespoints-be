class B2bPincodeAvailabilityService
  PINCODE_COORDS_CACHE_TTL = 12.hours

  def self.geocode_pincode(pincode)
    normalized = pincode.to_s.strip
    return nil if normalized.blank?

    cached = Rails.cache.read("b2b_pincode_coords:#{normalized}")
    return cached if cached.present?

    result = GoogleMapsService.instance.geocode("#{normalized}, India")
    return nil if result.blank?

    payload = {
      latitude: result[:latitude].to_f,
      longitude: result[:longitude].to_f
    }
    Rails.cache.write("b2b_pincode_coords:#{normalized}", payload, expires_in: PINCODE_COORDS_CACHE_TTL)
    payload
  end

  def initialize(pincode:,  product_id:, product_variant_id: nil, quantity:, buyer_dealer: nil, radius_km: nil)
    @pincode = pincode.to_s.strip.presence || auto_capture_pincode(buyer_dealer)
    @product_id = product_id
    @product_variant_id = product_variant_id
    @quantity = quantity.to_i
    @buyer_dealer = buyer_dealer
    @radius_km = radius_km
  end

  def call
    validate_pincode!

    coords = self.class.geocode_pincode(@pincode)
    raise StandardError, "Unable to locate pincode. Please enter a valid pincode." if coords.blank?

    sellers = find_eligible_sellers(coords)
    available_items_count = sellers.sum { |entry| entry[:stock_quantity].to_i }

    {
      deliverable: sellers.any?,
      message: build_message(sellers, available_items_count),
      sellers_count: sellers.count,
      available_items_count: available_items_count,
      latitude: coords[:latitude],
      longitude: coords[:longitude],
      pincode: @pincode
    }
  end

  private

  def auto_capture_pincode(buyer_dealer)
    return nil if buyer_dealer.blank?
    
    default_address = buyer_dealer.addresses.where(is_default: true).first ||
                      buyer_dealer.addresses.first
    default_address&.postal_code
  end

  def validate_pincode!
    raise StandardError, "Pincode is required" if @pincode.blank?
    raise StandardError, "Pincode must be 6 digits" unless @pincode.match?(/\A[1-9][0-9]{5}\z/)
  end

  def find_eligible_sellers(coords)
    scope = DealerProduct.live
                         .for_b2b
                         .includes(dealer: [:dealer_profile, :dealer_location])
                         .where(product_id: @product_id)
                         .where("dealer_products.stock_quantity >= ?", @quantity)

    scope = scope.where.not(dealer_id: @buyer_dealer.id) if @buyer_dealer.present?
    scope = scope.where(product_variant_id: @product_variant_id) if @product_variant_id.present?

    sellers = {}

    scope.find_each do |dealer_product|
      dealer = dealer_product.dealer
      location = dealer&.dealer_location
      next unless dealer&.status == "active"
      next unless location&.is_active?
      next if location.latitude.blank? || location.longitude.blank?

      distance_info = GoogleMapsService.instance.driving_distance(
        coords[:latitude],
        coords[:longitude],
        location.latitude.to_f,
        location.longitude.to_f
      )

      distance_km =
        if distance_info.present?
          distance_info[:distance_km]
        else
          DealerLocation.distance_km(
            coords[:latitude],
            coords[:longitude],
            location.latitude.to_f,
            location.longitude.to_f
          )
        end

      seller_radius = location.service_radius_km.to_f
      next if seller_radius <= 0
      next if distance_km > seller_radius
      stock = dealer_product.stock_quantity.to_i

      sellers[dealer.id] ||= {
        id: dealer.id,
        dealer_code: dealer.dealer_code,
        business_name: dealer.dealer_profile&.business_name,
        stock_quantity: 0,
        distance_km: distance_km.round(2),
      }

      sellers[dealer.id][:stock_quantity] += stock
    end

    sellers.values.sort_by { |entry| entry[:distance_km] }
  end

  def build_message(sellers, available_items_count)
    return "No sellers available for delivery to pincode #{@pincode}" if sellers.empty?

    if @product_variant_id.present?
      "#{available_items_count} item(s) available at pincode #{@pincode} from #{sellers.size} seller(s)"
    else
      "#{available_items_count} item(s) available at pincode #{@pincode}"
    end
  end
end
