class B2bDirectOrderService
  COD_LIMIT = 50_000.to_d

  def initialize(buyer:, dealer_product_id:, quantity:, latitude:, longitude:, radius_km:, payment_method: nil, payment_status: "pending", buyer_payment_attempt: nil, billing_address: {}, shipping_address: {}, pincode: nil)
    @buyer = buyer
    @dealer_product_id = dealer_product_id
    @quantity = quantity.to_i.positive? ? quantity.to_i : 1
    @latitude = latitude.to_f
    @longitude = longitude.to_f
    @radius_km = radius_km.to_i.positive? ? radius_km.to_i : 5
    @payment_method = payment_method
    @payment_status = payment_status.to_s.presence || "pending"
    @buyer_payment_attempt = buyer_payment_attempt
    @billing_address = normalize_address(billing_address)
    @shipping_address = normalize_address(shipping_address)
    @pincode = pincode.to_s.strip.presence
  end

  def call
    validate!
    resolve_coordinates!

    dealer_product = DealerProduct.live.includes(:product_variant, :dealer).find_by(id: @dealer_product_id)
    raise StandardError, "Product not available for B2B sale" unless dealer_product&.sellable_in_b2b?
    raise StandardError, "Cannot buy your own product" if dealer_product.dealer_id == @buyer.id
    raise StandardError, "Insufficient stock" if dealer_product.stock_quantity.to_i < @quantity

    availability = B2bPincodeAvailabilityService.new(
      pincode: order_pincode,
      dealer_product_id: dealer_product.id,
      product_variant_id: dealer_product.product_variant_id,
      buyer_dealer: @buyer,
      radius_km: @radius_km
    ).call
    raise StandardError, availability[:message] unless availability[:deliverable]

    seller = dealer_product.dealer
    raise StandardError, "Seller dealer is unavailable" unless seller&.status == "active"

    variant = dealer_product.product_variant
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
        requested_radius_km: @radius_km,
        current_broadcast_radius: 5,
        broadcast_attempts: 0,
        latitude: @latitude,
        longitude: @longitude,
        billing_address: @billing_address,
        shipping_address: @shipping_address,
        subtotal_amount: pricing[:subtotal],
        tax_amount: pricing[:gst_amount],
        discount_amount: 0,
        total_amount: pricing[:total],
        expires_at: 10.minutes.from_now,
        payment_method: @payment_method || "cod",
        payment_status: "pending",
        buyer_payment_attempt: @buyer_payment_attempt,
        is_direct_buy: false,
        source_type: "DealerProduct",
        source_id: dealer_product.id
      )

      item = B2bOrderItem.create!(
        b2b_order: order,
        product_variant_id: variant.id,
        quantity: @quantity,
        unit_price: pricing[:unit_price],
        total_price: pricing[:subtotal],
        dealer_product_id: dealer_product.id,
        status: "open"
      )

      B2bOrderBroadcastService.new(order: order, actor: @buyer, current_radius: 5).initial_broadcast!

      BroadcastB2bOrderJob.set(wait: 1.minute).perform_later(order.id)
    end

    order
  end

  private

  def validate!
    raise StandardError, "Delivery address is required" if @shipping_address.blank? || @shipping_address["address_line1"].blank?
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
    @pincode.presence ||
      @shipping_address["postal_code"].presence ||
      @billing_address["postal_code"].presence
  end

  def normalize_address(raw)
    return {} if raw.blank?

    payload = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    payload.stringify_keys.slice(
      "name", "phone", "address_line1", "address_line2", "city", "state",
      "country", "postal_code", "latitude", "longitude"
    )
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
