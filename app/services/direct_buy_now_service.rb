class DirectBuyNowService
  Result = Struct.new(:orders, :payment_data, keyword_init: true)

  def initialize(buyer:, product_variant_id:, quantity:, payment_method:, billing_address:, shipping_address:)
    @buyer = buyer
    @product_variant_id = product_variant_id
    @quantity = quantity.to_i.positive? ? quantity.to_i : 1
    @payment_method = payment_method.to_s.presence || "cod"
    @billing_address = billing_address || {}
    @shipping_address = shipping_address || {}
  end

  def call
    raise StandardError, "Invalid payment method" unless Order::PAYMENT_METHODS.include?(@payment_method)

    variant = ProductVariant.includes(:product).find_by(id: @product_variant_id)
    raise StandardError, "Product variant not found" unless variant
    raise StandardError, "Product not available" unless variant.product&.is_active
    raise StandardError, "Variant is not active" unless variant.is_active

    pricing = Pricing::PriceCalculator.new(
      variant: variant,
      quantity: @quantity,
      user_type: @buyer.is_a?(Dealer) ? :dealer : :account
    ).call

    unit_price = pricing[:unit_price]
    subtotal = pricing[:subtotal]
    tax = pricing[:gst_amount]
    total = pricing[:total]

    financials = MarketplaceOrderFinancials.build(order_total: total)

    orders = []
    payment_data = {}

    ActiveRecord::Base.transaction do
      order = Order.create!(
        buyer: @buyer,
        seller_dealer_id: nil,
        status: @payment_method == "cod" ? "processing" : "pending",
        subtotal_amount: subtotal,
        tax_amount: tax,
        discount_amount: pricing[:discount_amount],
        total_amount: total,
        coupon_code: nil,
        payment_method: @payment_method,
        payment_status: "pending",
        payment_gateway: @payment_method == "online" ? "cashfree" : nil,
        billing_address: @billing_address,
        shipping_address: @shipping_address,
        commission_rate: financials[:commission_rate],
        commission_amount: financials[:commission_amount],
        marketplace_fee_amount: financials[:marketplace_fee_amount],
        seller_settlement_amount: financials[:seller_settlement_amount],
        settlement_status: financials[:settlement_status],
        refund_status: financials[:refund_status],
        refund_amount: financials[:refund_amount]
      )

      OrderItem.create!(
        order: order,
        product_variant_id: variant.id,
        quantity: @quantity,
        unit_price: unit_price,
        total_price: subtotal
      )

      if @payment_method == "online"
        payment_data = create_cashfree_payment!(order)
      else
         order.update!(
          payment_status: "pending",
          status: "processing"
        )
        OrderNotificationJob.perform_later(order.id, "placed", @buyer.class.name, @buyer.id)
        OrderMailer.customer_order_confirmation(order.id).deliver_later
        OrderMailer.dealer_new_order(order.id).deliver_later if order.seller_dealer&.email.present?
        OrderMailer.admin_order_alert(order.id).deliver_later
      end

      orders << order
    end

    Result.new(orders: orders, payment_data: payment_data)
  end

  private

  def create_cashfree_payment!(order)
    service = CashfreeService.new
    payload = service.create_cashfree_order(
      reference: order.order_number,
      amount: order.total_amount,
      customer: @buyer,
      return_params: {
        order_id: order.id,
        order_number: order.order_number
      }
    )
      
    order.update!(
      gateway_order_reference: payload["cf_order_id"] || payload["order_id"],
      payment_session_id: payload["payment_session_id"],
      payment_gateway_payload: payload
    )

    {
      payment_session_id: payload["payment_session_id"],
      gateway_order_reference: order.gateway_order_reference,
      payment_attempt_id: nil,
      order_id: order.id,
      provider: "cashfree"
    }
  end
end