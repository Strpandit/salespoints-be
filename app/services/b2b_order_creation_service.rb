class B2bOrderCreationService
  COD_LIMIT = 50_000.to_d

  def initialize(buyer:, cart:, latitude:, longitude:, radius_km:, payment_method:, payment_status: "pending", buyer_payment_attempt: nil, cart_snapshot: nil)
    @buyer = buyer
    @cart = cart
    @latitude = latitude.to_f
    @longitude = longitude.to_f
    @radius_km = radius_km.to_i.positive? ? radius_km.to_i : 10
    @payment_method = payment_method.to_s.presence || "cod"
    @payment_status = payment_status.to_s.presence || "pending"
    @buyer_payment_attempt = buyer_payment_attempt
    @cart_snapshot = cart_snapshot&.stringify_keys
  end

  def call(clear_cart: true)
    raise StandardError, "Cart is empty" if snapshot_items.empty?
    raise StandardError, "Current location is required to place nearby B2B request" if @latitude.zero? || @longitude.zero?
    raise StandardError, "Invalid payment method" unless B2bOrder::PAYMENT_METHODS.include?(@payment_method)
    validate_cod_limit!

    order = nil
    ActiveRecord::Base.transaction do
      order = B2bOrder.create!(
        buyer_dealer_id: @buyer.id,
        status: "pending",
        requested_radius_km: @radius_km,
        latitude: @latitude,
        longitude: @longitude,
        subtotal_amount: snapshot_subtotal,
        tax_amount: snapshot_tax,
        discount_amount: snapshot_discount,
        total_amount: snapshot_total,
        coupon_code: snapshot_coupon_code,
        expires_at: 20.minutes.from_now,
        payment_method: @payment_method,
        payment_status: @payment_status,
        buyer_payment_attempt: @buyer_payment_attempt
      )

      snapshot_items.each do |ci|
        B2bOrderItem.create!(
          b2b_order: order,
          product_variant_id: ci.fetch("product_variant_id"),
          quantity: ci.fetch("quantity"),
          unit_price: ci.fetch("unit_price"),
          total_price: ci.fetch("total_price")
        )
      end

      B2bOrderBroadcastService.new(order: order, actor: @buyer).initial_broadcast!
      clear_cart_state! if clear_cart
    end

    order
  end

  private

  def validate_cod_limit!
    return unless @payment_method == "cod"
    return if snapshot_total <= COD_LIMIT

    raise StandardError, "COD is allowed only up to Rs 50,000 for B2B requests"
  end

  def clear_cart_state!
    return if @cart.blank?

    @cart.clear
    @cart.remove_coupon!
  end

  def snapshot_items
    return @snapshot_items if defined?(@snapshot_items)

    @snapshot_items =
      if @cart_snapshot.present?
        Array(@cart_snapshot["items"]).map(&:stringify_keys)
      else
        @cart.cart_items.includes(:product_variant).map do |ci|
          {
            "product_variant_id" => ci.product_variant_id,
            "quantity" => ci.quantity,
            "unit_price" => ci.unit_price.to_d,
            "total_price" => ci.total_price.to_d
          }
        end
      end
  end

  def snapshot_subtotal
    @cart_snapshot.present? ? @cart_snapshot.fetch("subtotal_amount", 0).to_d : @cart.subtotal_amount.to_d
  end

  def snapshot_tax
    @cart_snapshot.present? ? @cart_snapshot.fetch("tax_amount", 0).to_d : @cart.tax_amount.to_d
  end

  def snapshot_discount
    @cart_snapshot.present? ? @cart_snapshot.fetch("discount_amount", 0).to_d : @cart.coupon_discount_amount.to_d
  end

  def snapshot_total
    @cart_snapshot.present? ? @cart_snapshot.fetch("total_amount", 0).to_d : @cart.grand_total.to_d
  end

  def snapshot_coupon_code
    @cart_snapshot.present? ? @cart_snapshot["coupon_code"] : @cart.coupon_code
  end
end
