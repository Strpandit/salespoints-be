class B2bWholesalerDirectOrderService
  include Rails.application.routes.url_helpers
  COD_LIMIT = 50_000.to_d
  GST_PERCENTAGE = 18.0

  def initialize(buyer:, seller:, wholesaler_post:, quantity:, latitude:, longitude:, requested_radius_km: nil, payment_method: nil, payment_status: "pending", buyer_payment_attempt: nil)
    @buyer = buyer
    @seller = seller
    @wholesaler_post = wholesaler_post
    @quantity = quantity.to_i.positive? ? quantity.to_i : 1
    @latitude = latitude.to_f
    @longitude = longitude.to_f
    @requested_radius_km = requested_radius_km || 5.0
    @payment_method = payment_method
    @payment_status = payment_status.to_s.presence || "pending"
    @buyer_payment_attempt = buyer_payment_attempt
  end

  def call
    validate!

    unit_price = @wholesaler_post.price.to_f

    if unit_price <= 0
      raise StandardError, "Product price is not set or invalid"
    end

    if @requested_radius_km <= 0
      raise "Requested radius km must be greater than 0"
    end
    
    raise StandardError, "Insufficient stock" if @wholesaler_post.stock_quantity.to_i < @quantity

    subtotal = unit_price * @quantity
    gst_amount = calculate_gst(unit_price, @quantity)
    total_amount = subtotal

    if @payment_method.present? && @payment_method == "cod"
      check_cod_limit(total_amount)
    end

    order = nil

    ActiveRecord::Base.transaction do
      order = B2bOrder.create!(
        buyer_dealer_id: @buyer.id,
        seller_dealer_id: @seller.id,
        request_status: "pending_request",
        status: "pending_payment",
        requested_at: Time.current,
        requested_radius_km: @requested_radius_km,
        latitude: @latitude,
        longitude: @longitude,
        subtotal_amount: subtotal,
        tax_amount: gst_amount,
        discount_amount: 0,
        total_amount: total_amount,
        expires_at: 4.hours.from_now,
        payment_method: @payment_method || "cod",
        payment_status: @payment_status,
        buyer_payment_attempt: @buyer_payment_attempt,
        is_direct_buy: true,
        source_type: "WholesalerPost",
        source_id: @wholesaler_post.id
      )

      item = B2bOrderItem.create!(
        b2b_order: order,
        product_variant_id: nil,
        quantity: @quantity,
        unit_price: unit_price,
        total_price: subtotal,
        dealer_product_id: @wholesaler_post.dealer_product_id || nil,
        wholesaler_post_id: @wholesaler_post.id,
        status: "open"
      )

      offer = B2bOrderOffer.create!(
        b2b_order: order,
        dealer: @seller,
        status: "open",
        delivery_channel: "whatsapp",
        item_ids: [item.id],
        delivery_payload: {
          request_id: order.id,
          wholesaler_post_id: @wholesaler_post.id,
          post_title: @wholesaler_post.title,
          product_name: @wholesaler_post.title,
          quantity: item.quantity,
          unit_price: item.unit_price.to_f,
          total_price: item.total_price.to_f,
          buyer_name: @buyer.dealer_code,
          buyer_phone: formatted_phone_for(@buyer)
        },
        accept_token: "b2b_accept_#{SecureRandom.hex(8)}",
        reject_token: "b2b_reject_#{SecureRandom.hex(8)}",
        recipient_phone: formatted_phone_for(@seller),
        expires_at: order.expires_at,
        rebroadcast_count: 0,
        whatsapp_status: "pending"
      )
    end

    order
  end

  private

  def validate!
    raise StandardError, "Current location is required" if @latitude.zero? || @longitude.zero?
    if @payment_method.present? && !B2bOrder::PAYMENT_METHODS.include?(@payment_method)
      raise StandardError, "Invalid payment method"
    end
  end

  def calculate_gst(unit_price, quantity)
    (unit_price * GST_PERCENTAGE / (100 + GST_PERCENTAGE)) * quantity
  end

  def check_cod_limit(total)
    if @payment_method == "cod" && total > COD_LIMIT
      raise StandardError, "COD is allowed only up to Rs 50,000"
    end
  end

  def formatted_phone_for(dealer)
    return nil if dealer.phone.blank?
    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
  end
end
