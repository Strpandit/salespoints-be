class DirectBuyNowService
  Result = Struct.new(:order, :payment_data, keyword_init: true)

  def initialize(buyer:, product_variant_id:, quantity:, payment_method:, 
                 billing_address:, shipping_address:, pincode:)
    @buyer = buyer
    @product_variant_id = product_variant_id
    @quantity = quantity.to_i.positive? ? quantity.to_i : 1
    @payment_method = payment_method.to_s.presence || "cod"
    @billing_address = billing_address || {}
    @shipping_address = shipping_address || {}
    @pincode = pincode.to_s.strip
  end

  def call
    raise StandardError, "Invalid payment method" unless Order::PAYMENT_METHODS.include?(@payment_method)
    raise StandardError, "Pincode is required for delivery" if @pincode.blank?

    variant = ProductVariant.includes(:product).find_by(id: @product_variant_id)
    raise StandardError, "Product variant not found" unless variant
    raise StandardError, "Product not available" unless variant.product&.is_active
    raise StandardError, "Variant is not active" unless variant.is_active

    eligible_dealers = find_eligible_dealers(variant)
    raise StandardError, "No sellers available for delivery in your pincode" if eligible_dealers.empty?

    pricing = Pricing::PriceCalculator.new(
      variant: variant,
      quantity: @quantity,
      user_type: :account
    ).call

    order = nil
    payment_data = {}

    ActiveRecord::Base.transaction do
      order = Order.create!(
        buyer: @buyer,
        seller_dealer_id: nil,
        status: "pending",
        subtotal_amount: pricing[:subtotal],
        tax_amount: pricing[:gst_amount],
        discount_amount: pricing[:discount_amount],
        total_amount: pricing[:total],
        coupon_code: nil,
        payment_method: @payment_method,
        payment_status: @payment_method == "cod" ? "pending" : "paid",
        payment_gateway: @payment_method == "online" ? "cashfree" : nil,
        billing_address: @billing_address,
        shipping_address: @shipping_address,
        commission_rate: 0,
        commission_amount: 0,
        marketplace_fee_amount: 0,
        seller_settlement_amount: 0,
        settlement_status: "pending",
        refund_status: "none",
        refund_amount: 0,
        placed_at: Time.current,
        expires_at: 4.hours.from_now
      )

      OrderItem.create!(
        order: order,
        product_variant_id: variant.id,
        quantity: @quantity,
        unit_price: pricing[:unit_price],
        total_price: pricing[:subtotal]
      )

      if @payment_method == "online"
        payment_data = create_online_payment(order)
      end

      B2bOrderBroadcastService.new(
        order: order,
        actor: @buyer,
        current_radius: 10,
        is_b2c: true
      ).initial_broadcast!

      ExpireB2cOrderJob.set(wait: 4.hours).perform_later(order.id)

      create_buyer_waiting_notification(order)
    end

    Result.new(order: order, payment_data: payment_data)
  end

  private

  def find_eligible_dealers(variant)
    Dealer.active
          .includes(:dealer_products)
          .where(dealer_products: {
            product_variant_id: variant.id,
            sell_in_b2c: true,
            is_active: true,
            approve_status: "approved"
          })
          .where("dealer_products.stock_quantity > 0")
          .where(pincode: @pincode)
          .distinct
  end

  def create_online_payment(order)
    attempt = PaymentAttempt.create!(
      buyer: @buyer,
      status: "pending",
      amount: order.total_amount,
      currency: "INR",
      payment_gateway: "cashfree",
      result_payload: {
        checkout_context: "b2c_order",
        order_ids: [order.id],
        request_metadata: {
          order_id: order.id,
          product_variant_id: @product_variant_id,
          quantity: @quantity,
          pincode: @pincode
        }
      }
    )

    cashfree = CashfreeService.new
    payload = cashfree.create_cashfree_order(
      reference: attempt.attempt_number,
      amount: attempt.amount,
      customer: @buyer,
      return_params: {
        payment_attempt_id: attempt.id,
        order_id: order.id
      }
    )

    attempt.update!(
      gateway_order_reference: payload["cf_order_id"] || payload["order_id"],
      payment_session_id: payload["payment_session_id"],
      payment_gateway_payload: payload
    )

    {
      payment_session_id: attempt.payment_session_id,
      gateway_order_reference: attempt.gateway_order_reference,
      payment_attempt_id: attempt.id,
      provider: "cashfree"
    }
  end

  def create_buyer_waiting_notification(order)
    NotificationService.deliver(
      recipient: @buyer,
      actor: @buyer,
      notifiable: order,
      kind: "b2c_order_waiting",
      title: "⏳ Order Placed - Waiting for Seller",
      message: "Your order ##{order.order_number} has been placed. We're waiting for a seller to accept it.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.order_number,
        status: "pending",
        total_amount: order.total_amount.to_f,
        expires_at: 4.hours.from_now
      }
    )
  end
end