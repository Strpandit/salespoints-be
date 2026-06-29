class OnlinePaymentAttemptService
  Result = Struct.new(:attempt, :payment_data, keyword_init: true)

  def initialize(buyer:, billing_address:, shipping_address:, context: "retail_order", metadata: {})
    @buyer = buyer
    @billing_address = billing_address || {}
    @shipping_address = shipping_address || {}
    @context = context
    @metadata = metadata || {}
  end

  def call

    attempt = nil
    payment_data = {}

    ActiveRecord::Base.transaction do
      # validate_coupon!

      attempt = PaymentAttempt.create!(
        buyer: @buyer,
        status: "pending",
        currency: "INR",
        billing_address: @billing_address,
        shipping_address: @shipping_address,
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

end
