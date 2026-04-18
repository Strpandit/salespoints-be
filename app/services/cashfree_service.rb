class CashfreeService
  include HTTParty

  DEFAULT_API_VERSION = "2023-08-01".freeze

  def initialize
    @client_id = ENV["CASHFREE_CLIENT_ID"].to_s
    @client_secret = ENV["CASHFREE_CLIENT_SECRET"].to_s
    @base_url = ENV["CASHFREE_BASE_URL"].presence || "https://sandbox.cashfree.com/pg"
    @frontend_url = ENV["FRONTEND_URL"].presence || "http://localhost:5173"
  end

  def configured?
    @client_id.present? && @client_secret.present?
  end

  def create_order(order:, customer:)
    create_cashfree_order(
      reference: order.order_number,
      amount: order.total_amount,
      customer: customer,
      return_params: { order_id: order.id, order_number: order.order_number }
    )
  end

  def create_payment_attempt(attempt:, customer:)
    create_cashfree_order(
      reference: attempt.attempt_number,
      amount: attempt.amount,
      customer: customer,
      return_params: { payment_attempt_id: attempt.id, attempt_number: attempt.attempt_number }
    )
  end

  def create_cashfree_order(reference:, amount:, customer:, return_params:)
    raise StandardError, "Cashfree is not configured" unless configured?

    response = self.class.post(
      "#{@base_url}/orders",
      headers: default_headers,
      body: {
        order_id: reference,
        order_amount: amount.to_f.round(2),
        order_currency: "INR",
        customer_details: customer_details_for(customer),
        order_meta: {
          return_url: "#{@frontend_url}/cart?cashfree_return=1&#{return_params.to_query}"
        }
      }.to_json
    )

    parsed = parse_response(response)
    if response.success? && parsed["payment_session_id"].present?
      parsed
    else
      raise StandardError, parsed["message"].presence || parsed["error"] || "Unable to create Cashfree payment session"
    end
  end

  def fetch_order(order_reference)
    raise StandardError, "Cashfree is not configured" unless configured?
    raise StandardError, "Cashfree order reference is missing" if order_reference.blank?

    response = self.class.get(
      "#{@base_url}/orders/#{order_reference}",
      headers: default_headers
    )

    parse_response(response)
  end

  private

  def default_headers
    {
      "Content-Type" => "application/json",
      "x-api-version" => ENV["CASHFREE_API_VERSION"].presence || DEFAULT_API_VERSION,
      "x-client-id" => @client_id,
      "x-client-secret" => @client_secret
    }
  end

  def customer_details_for(customer)
    customer_name =
      if customer.respond_to?(:full_name)
        customer.full_name
      else
        [customer.try(:first_name), customer.try(:last_name)].compact.join(" ").presence || customer.try(:email) || "SalesPoints Customer"
      end

    raw_phone = customer.try(:phone).to_s.gsub(/\D/, "")
    safe_phone = raw_phone.presence || "9999999999"

    {
      customer_id: "#{customer.class.name.first(3).upcase}-#{customer.id}",
      customer_name: customer_name,
      customer_email: customer.try(:email).presence || "support@salespoints.com",
      customer_phone: safe_phone
    }
  end

  def parse_response(response)
    body = response.respond_to?(:parsed_response) ? response.parsed_response : response
    body.is_a?(Hash) ? body : {}
  end
end
