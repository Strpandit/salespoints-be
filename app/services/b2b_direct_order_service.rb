class B2bDirectOrderService
  COD_LIMIT = 50_000.to_d

  def initialize(buyer:, dealer_product_id:, quantity:, latitude:, longitude:, radius_km:, payment_method:, payment_status: "pending", buyer_payment_attempt: nil)
    @buyer = buyer
    @dealer_product_id = dealer_product_id
    @quantity = quantity.to_i.positive? ? quantity.to_i : 1
    @latitude = latitude.to_f
    @longitude = longitude.to_f
    @radius_km = radius_km.to_i.positive? ? radius_km.to_i : 10
    @payment_method = payment_method.to_s.presence || "cod"
    @payment_status = payment_status.to_s.presence || "pending"
    @buyer_payment_attempt = buyer_payment_attempt
  end

  def call
    raise StandardError, "Current location is required to place B2B request" if @latitude.zero? || @longitude.zero?
    raise StandardError, "Invalid payment method" unless B2bOrder::PAYMENT_METHODS.include?(@payment_method)

    dealer_product = DealerProduct.live.includes(:product_variant, :dealer).find_by(id: @dealer_product_id)
    raise StandardError, "Product not available" unless dealer_product&.sellable?
    raise StandardError, "Insufficient stock" if dealer_product.stock_quantity.to_i < @quantity
    raise StandardError, "Cannot buy your own product" if dealer_product.dealer_id == @buyer.id

    seller = dealer_product.dealer
    raise StandardError, "Seller dealer is unavailable" unless seller&.status == "active"

    variant = dealer_product.product_variant

    pricing = Pricing::PriceCalculator.new(
      variant: variant,
      quantity: @quantity,
      user_type: :dealer
    ).call

    unit_price = pricing[:unit_price]
    subtotal  = pricing[:subtotal]
    taxable_amount  = pricing[:taxable_amount]
    tax       = pricing[:gst_amount]
    total     = pricing[:total]

    raise StandardError, "COD is allowed only up to Rs 50,000 for B2B requests" if @payment_method == "cod" && total > COD_LIMIT

    order = nil

    ActiveRecord::Base.transaction do
      order = B2bOrder.create!(
        buyer_dealer_id: @buyer.id,
        seller_dealer_id: seller.id,
        status: "pending",
        requested_radius_km: @radius_km,
        latitude: @latitude,
        longitude: @longitude,
        subtotal_amount: subtotal,
        tax_amount: tax,
        discount_amount: 0,
        total_amount: total,
        coupon_code: nil,
        expires_at: 20.minutes.from_now,
        payment_method: @payment_method,
        payment_status: @payment_status,
        buyer_payment_attempt: @buyer_payment_attempt
      )

      item = B2bOrderItem.create!(
        b2b_order: order,
        product_variant_id: variant.id,
        quantity: @quantity,
        unit_price: unit_price,
        total_price: subtotal
      )

      offer = B2bOrderOffer.create!(
        b2b_order: order,
        dealer: seller,
        status: "open",
        delivery_channel: "whatsapp",
        item_ids: [item.id],
        delivery_payload: [{ id: item.id, quantity: @quantity, unit_price: unit_price.to_f, total_price: subtotal.to_f }],
        accept_token: "b2b_accept_#{SecureRandom.hex(8)}",
        reject_token: "b2b_reject_#{SecureRandom.hex(8)}",
        recipient_phone: formatted_phone_for(seller),
        expires_at: order.expires_at,
        rebroadcast_count: 0
      )

      NotificationService.deliver(
        recipient: seller,
        actor: @buyer,
        notifiable: order,
        kind: "b2b_order_request",
        title: "New B2B order request",
        message: "A dealer placed a direct buy request for #{@quantity} unit(s).",
        visible_in_app: true,
        delivery_channels: { push: true, whatsapp: true, sms: false, email: false, in_app: true },
        payload: {
          offer_id: offer.id,
          order_id: order.id,
          buyer_dealer_id: @buyer.id,
          dealer_id: seller.id,
          item_ids: [item.id],
          direct: true
        }
      )
    end

    order
  end

  private

  def formatted_phone_for(dealer)
    return nil if dealer.phone.blank?

    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
  end
end
