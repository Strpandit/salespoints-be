class DirectBuyNowService
  Result = Struct.new(:orders, :payment_data, keyword_init: true)

  def initialize(buyer:, dealer_product_id:, quantity:, payment_method:, billing_address:, shipping_address:)
    @buyer = buyer
    @dealer_product_id = dealer_product_id
    @quantity = quantity.to_i.positive? ? quantity.to_i : 1
    @payment_method = payment_method.to_s.presence || "cod"
    @billing_address = billing_address || {}
    @shipping_address = shipping_address || {}
  end

  def call
    raise StandardError, "Invalid payment method" unless Order::PAYMENT_METHODS.include?(@payment_method)

    dealer_product = DealerProduct.live.includes(:product_variant, :dealer, :product).find_by(id: @dealer_product_id)
    raise StandardError, "Product not available" unless dealer_product&.sellable?
    raise StandardError, "Insufficient stock for #{dealer_product.product&.name || 'item'}" if dealer_product.stock_quantity.to_i < @quantity
    raise StandardError, "Dealer cannot buy their own product" if @buyer.is_a?(Dealer) && dealer_product.dealer_id == @buyer.id

    variant = dealer_product.product_variant
    pricing = Pricing::PriceCalculator.new(
      variant: variant,
      quantity: @quantity,
      user_type: @buyer.is_a?(Dealer) ? :dealer : :account
    ).call

    unit_price = pricing[:unit_price]
    subtotal = pricing[:subtotal]
    tax = pricing[:gst_amount]
    taxable_amount = pricing[:taxable_amount]
    total = pricing[:total]

    financials = MarketplaceOrderFinancials.build(order_total: total)

    orders = []
    payment_data = {}

    ActiveRecord::Base.transaction do
      order = Order.create!(
        buyer: @buyer,
        seller_dealer_id: dealer_product.dealer_id,
        status: "pending",
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
        dealer_product_id: dealer_product.id,
        product_variant_id: variant.id,
        quantity: @quantity,
        unit_price: unit_price,
        total_price: subtotal
      )

      dealer_product.update!(stock_quantity: dealer_product.stock_quantity.to_i - @quantity)

      if @payment_method == "online"
        payment_data = create_cashfree_payment!(order)
      end

      orders << order
    end

    orders.each do |order|
      OrderNotificationJob.perform_later(order.id, "placed", @buyer.class.name, @buyer.id)
    end

    Result.new(orders: orders, payment_data: payment_data)
  end

  private

  def create_cashfree_payment!(order)
    service = CashfreeService.new
    payload = service.create_order(order: order, customer: @buyer)

    order.update!(
      gateway_order_reference: payload["cf_order_id"] || payload["order_id"] || order.order_number,
      payment_session_id: payload["payment_session_id"],
      payment_gateway_payload: payload
    )

    {
      payment_session_id: payload["payment_session_id"],
      gateway_order_reference: order.gateway_order_reference,
      order_id: order.id,
      provider: "cashfree"
    }
  end
end
