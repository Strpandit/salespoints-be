class OrderCheckoutService
  Result = Struct.new(:orders, :payment_data, keyword_init: true)

  def initialize(cart:, buyer:, payment_method:, billing_address:, shipping_address:)
    @cart = cart
    @buyer = buyer
    @payment_method = payment_method.to_s.presence || "cod"
    @billing_address = billing_address || {}
    @shipping_address = shipping_address || {}
  end

  def call
    raise StandardError, "Cart is empty" if @cart.blank? || @cart.cart_items.empty?
    raise StandardError, "Invalid payment method" unless Order::PAYMENT_METHODS.include?(@payment_method)

    orders = []
    payment_data = {}

    ActiveRecord::Base.transaction do
      validate_coupon!

      cart_items = @cart.cart_items.includes(:product_variant, dealer_product: [:dealer, :product])
      grouped_items = cart_items.group_by { |ci| ci.dealer_product&.dealer_id }
      raise StandardError, "Dealer mapping is missing for one or more items" if grouped_items.keys.any?(&:blank?)

      if @payment_method == "online" && grouped_items.size > 1
        raise StandardError, "Online payment currently supports single-dealer checkout only. Please place separate orders or choose COD."
      end

      discount_remaining = @cart.coupon_discount_amount.to_d

      grouped_items.each do |dealer_id, items|
        subtotal = 0.to_d
        tax = 0.to_d

        pricing_rows = []

        items.each do |ci|
          dp = ci.dealer_product

          raise StandardError, "Product not available" if dp.blank? || !dp.sellable?

          raise StandardError, "Insufficient stock for #{dp.product&.name || 'item'}" if dp.stock_quantity.to_i < ci.quantity.to_i

          pricing = Pricing::PriceCalculator.new(
            variant: ci.product_variant,
            quantity: ci.quantity,
            user_type: @buyer.is_a?(Dealer) ? :dealer : :account
          ).call

          subtotal += pricing[:subtotal]
          tax += pricing[:gst_amount]

          pricing_rows << [ci, pricing]
        end

        share =
          if @cart.subtotal_amount.to_d.positive?
            subtotal / @cart.subtotal_amount.to_d
          else
            0
          end

        discount =
          if index == grouped_items.size - 1
            discount_remaining
          else
            allocated = (@cart.coupon_discount_amount.to_d * share).round(2)
            discount_remaining -= allocated
            allocated
          end

        total = subtotal - discount
        financials = MarketplaceOrderFinancials.build(order_total: total)

        order = Order.create!(
          buyer: @buyer,
          seller_dealer_id: dealer_id,
          status: "pending",
          subtotal_amount: subtotal,
          tax_amount: tax,
          discount_amount: discount,
          total_amount: total,
          coupon_code: @cart.coupon_code,
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

        pricing_rows.each do |ci, pricing|          
          OrderItem.create!(
            order: order,
            dealer_product_id: ci.dealer_product_id,
            product_variant_id: ci.product_variant_id,
            quantity: ci.quantity,
            unit_price: pricing[:unit_price],
            total_price: pricing[:subtotal]
          )

          ci.dealer_product.update!(
              stock_quantity: ci.dealer_product.stock_quantity.to_i - ci.quantity.to_i
            )
        end

        orders << order
      end

      @cart.coupon.consume_for!(@buyer) if @cart.coupon.present?

      if @payment_method == "online"
        payment_data = create_cashfree_payment!(orders.first)
      end

      @cart.clear
      @cart.remove_coupon!
    end

    orders.each do |order|
      OrderNotificationJob.perform_later(order.id, "placed", @buyer.class.name, @buyer.id)
    end

    Result.new(orders: orders, payment_data: payment_data)
  end

  private

  def validate_coupon!
    return unless @cart.coupon.present?

    valid, message = @cart.coupon.validate_for_cart!(cart: @cart, user: @buyer)
    raise StandardError, message unless valid
  end

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
