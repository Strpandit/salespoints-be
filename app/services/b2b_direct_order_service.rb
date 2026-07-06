class B2bDirectOrderService
  COD_LIMIT = 50_000.to_d

  def initialize(buyer:, dealer_product_id:, quantity:, latitude:, longitude:, radius_km:, payment_method: nil, payment_status: "pending", buyer_payment_attempt: nil)
    @buyer = buyer
    @dealer_product_id = dealer_product_id
    @quantity = quantity.to_i.positive? ? quantity.to_i : 1
    @latitude = latitude.to_f
    @longitude = longitude.to_f
    @radius_km = radius_km.to_i.positive? ? radius_km.to_i : 5
    @payment_method = payment_method
    @payment_status = payment_status.to_s.presence || "pending"
    @buyer_payment_attempt = buyer_payment_attempt
  end

  def call
    validate!

    dealer_product = DealerProduct.live.includes(:product_variant, :dealer).find_by(id: @dealer_product_id)
    raise StandardError, "Product not available" unless dealer_product&.sellable?
    raise StandardError, "Cannot buy your own product" if dealer_product.dealer_id == @buyer.id
    raise StandardError, "Insufficient stock" if dealer_product.stock_quantity.to_i < @quantity

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
        subtotal_amount: pricing[:subtotal],
        tax_amount: pricing[:gst_amount],
        discount_amount: 0,
        total_amount: pricing[:total],
        expires_at: 10.minutes.from_now,
        payment_method: @payment_method || "cod",
        payment_status: "pending",
        buyer_payment_attempt: @buyer_payment_attempt,
        is_direct_buy: true,
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
    raise StandardError, "Current location is required" if @latitude.zero? || @longitude.zero?
    raise StandardError, "Invalid payment method" unless B2bOrder::PAYMENT_METHODS.include?(@payment_method)
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
