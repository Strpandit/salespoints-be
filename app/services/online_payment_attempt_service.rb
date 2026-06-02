class OnlinePaymentAttemptService
  Result = Struct.new(:attempt, :payment_data, keyword_init: true)

  def initialize(cart:, buyer:, billing_address:, shipping_address:, context: "retail_order", metadata: {})
    @cart = cart
    @buyer = buyer
    @billing_address = billing_address || {}
    @shipping_address = shipping_address || {}
    @context = context
    @metadata = metadata || {}
  end

  def call
    raise StandardError, "Cart is empty" if @cart.blank? || @cart.cart_items.empty?

    attempt = nil
    payment_data = {}

    ActiveRecord::Base.transaction do
      validate_coupon!

      attempt = PaymentAttempt.create!(
        buyer: @buyer,
        status: "pending",
        amount: @cart.grand_total,
        currency: "INR",
        coupon_code: @cart.coupon_code,
        billing_address: @billing_address,
        shipping_address: @shipping_address,
        cart_snapshot: build_cart_snapshot,
        result_payload: {
          checkout_context: @context,
          request_metadata: @metadata
        }
      )

      payload = CashfreeService.new.create_payment_attempt(attempt: attempt, customer: @buyer)
      attempt.update!(
        gateway_order_reference: payload["cf_order_id"] || payload["order_id"] || attempt.attempt_number,
        payment_session_id: payload["payment_session_id"],
        payment_gateway_payload: payload
      )

      payment_data = {
        payment_session_id: attempt.payment_session_id,
        gateway_order_reference: attempt.gateway_order_reference,
        payment_attempt_id: attempt.id,
        provider: "cashfree"
      }
    end

    Result.new(attempt: attempt, payment_data: payment_data)
  end

  private

  def validate_coupon!
    return unless @cart.coupon.present?

    valid, message = @cart.coupon.validate_for_cart!(cart: @cart, user: @buyer)
    raise StandardError, message unless valid
  end

  def build_cart_snapshot
    items = @cart.cart_items.includes(:product_variant, dealer_product: [:dealer, :product]).map do |item|
      {
        cart_item_id: item.id,
        dealer_product_id: item.dealer_product_id,
        dealer_id: item.dealer_product&.dealer_id,
        product_variant_id: item.product_variant_id,
        quantity: item.quantity,
        unit_price: item.unit_price.to_d.to_s,
        total_price: item.total_price.to_d.to_s
      }
    end

    {
      subtotal_amount: @cart.subtotal_amount.to_d.to_s,
      tax_amount: @cart.tax_amount.to_d.to_s,
      discount_amount: @cart.coupon_discount_amount.to_d.to_s,
      total_amount: @cart.grand_total.to_d.to_s,
      coupon_code: @cart.coupon_code,
      items: items
    }
  end
end
