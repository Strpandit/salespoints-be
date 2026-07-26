class B2bDirectOrderService
  COD_LIMIT = 50_000.to_d
  INITIAL_RADIUS = 10

  def initialize(buyer:, product_id:, product_variant_id:, quantity:, payment_method: nil, payment_status: "pending", buyer_payment_attempt: nil, pincode: nil, delivery_address: nil, use_business_address: true)
    @buyer = buyer
    @product_id = product_id
    @product_variant_id = product_variant_id
    @quantity = quantity.to_i.positive? ? quantity.to_i : 1
    @payment_method = payment_method
    @payment_status = payment_status.to_s.presence || "pending"
    @buyer_payment_attempt = buyer_payment_attempt
    @pincode = pincode.to_s.strip.presence
    @delivery_address = delivery_address
    @use_business_address = use_business_address
  end

  def call
    validate!

    delivery_coords = resolve_delivery_coordinates!
    buyer_coords = get_buyer_coordinates

    variant = ProductVariant.find_by(id: @product_variant_id)
    raise StandardError, "Product variant not found" unless variant

    pricing = calculate_pricing(variant)
    if @payment_method.present? && @payment_method == "cod"
      check_cod_limit(pricing[:total])
    end

    order = nil

    ActiveRecord::Base.transaction do
      order = B2bOrder.create!(
        buyer_dealer_id: @buyer.id,
        seller_dealer_id: nil,
        request_status: "pending_request",
        status: "pending_request",
        requested_at: Time.current,
        requested_radius_km: INITIAL_RADIUS,
        current_broadcast_radius: INITIAL_RADIUS,
        broadcast_attempts: 0,
        latitude: delivery_coords[:latitude],
        longitude: delivery_coords[:longitude],
        subtotal_amount: pricing[:subtotal],
        tax_amount: pricing[:gst_amount],
        discount_amount: 0,
        total_amount: pricing[:total],
        expires_at: 4.hours.from_now,
        payment_method: @payment_method || "cod",
        payment_status: "pending",
        buyer_payment_attempt: @buyer_payment_attempt,
        is_direct_buy: false,
        source_type: "b2b",
        source_id: @product_id
      )

      item = B2bOrderItem.create!(
        b2b_order: order,
        product_variant_id: variant.id,
        quantity: @quantity,
        unit_price: pricing[:unit_price],
        total_price: pricing[:subtotal],
        dealer_product_id: nil,
        status: "open"
      )

      broadcast_center = if @use_business_address
          :buyer
        else
          :delivery
        end

      B2bOrderBroadcastService.new(order: order, actor: @buyer, current_radius: INITIAL_RADIUS, broadcast_center: broadcast_center).initial_broadcast!

      BroadcastB2bOrderJob.set(wait: 1.minute).perform_later(order.id)
    end

    order
  end

  private

  def validate!
    raise StandardError, "Product variant is required" if @product_variant_id.blank?
    raise StandardError, "Delivery pincode is required" if order_pincode.blank?
  end

  def resolve_delivery_coordinates!

    if @delivery_address.present?
      return {
        latitude: @delivery_address.latitude,
        longitude: @delivery_address.longitude
      }
    end

    if @use_business_address
      location = @buyer.dealer_location
      if location&.latitude.present?
        return {
          latitude: location.latitude,
          longitude: location.longitude
        }
      end
    end

    coords = B2bPincodeAvailabilityService.geocode_pincode(order_pincode)
    raise StandardError, "Unable to locate delivery pincode" if coords.blank?

    {
      latitude: coords[:latitude],
      longitude: coords[:longitude]
    }
  end

  def get_buyer_coordinates
    location = @buyer.dealer_location
    if location&.latitude.present? && location&.longitude.present?
      { latitude: location.latitude, longitude: location.longitude }
    else
      address = @buyer.dealer_profile&.business_address
      coords = GoogleMapsService.instance.geocode(address)
      { latitude: coords[:latitude], longitude: coords[:longitude] }
    end
  end

  def order_pincode
    @pincode
  end

  def calculate_pricing(variant)
    Pricing::PriceCalculator.new(
      variant: variant,
      quantity: @quantity,
      user_type: :dealer
    ).call
  end

  def check_cod_limit(total)
    if @payment_method == "cod" && total > COD_LIMIT
      raise StandardError, "COD is allowed only up to Rs 50,000"
    end
  end
end
