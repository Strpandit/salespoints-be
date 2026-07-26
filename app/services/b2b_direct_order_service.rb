class B2bDirectOrderService
  COD_LIMIT = 50_000.to_d
  INITIAL_RADIUS = 10

  def initialize(buyer:, product_id:, product_variant_id:, quantity:, latitude:, longitude:, payment_method: nil, payment_status: "pending", buyer_payment_attempt: nil, pincode: nil)
    @buyer = buyer
    @product_id = product_id
    @product_variant_id = product_variant_id
    @quantity = quantity.to_i.positive? ? quantity.to_i : 1
    @latitude = latitude.to_f
    @longitude = longitude.to_f
    @payment_method = payment_method
    @payment_status = payment_status.to_s.presence || "pending"
    @buyer_payment_attempt = buyer_payment_attempt
    @pincode = pincode.to_s.strip.presence
  end

  def call
    validate!
    resolve_coordinates!   

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
        latitude: @latitude,
        longitude: @longitude,
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

      B2bOrderBroadcastService.new(order: order, actor: @buyer, current_radius: INITIAL_RADIUS).initial_broadcast!

      BroadcastB2bOrderJob.set(wait: 1.minute).perform_later(order.id)
    end

    order
  end

  private

  def validate!
    raise StandardError, "Product variant is required" if @product_variant_id.blank?
    raise StandardError, "Delivery pincode is required" if order_pincode.blank?
  end

  def resolve_coordinates!
    return if @latitude.nonzero? && @longitude.nonzero?

    coords = B2bPincodeAvailabilityService.geocode_pincode(order_pincode)
    raise StandardError, "Unable to locate delivery pincode" if coords.blank?

    @latitude = coords[:latitude]
    @longitude = coords[:longitude]
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
