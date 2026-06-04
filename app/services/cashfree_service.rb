class CashfreeService
  include HTTParty

  DEFAULT_API_VERSION = "2023-08-01".freeze
  PAYOUT_API_VERSION = "2023-08-01".freeze
  WEBHOOK_TOLERANCE_SECONDS = 5.minutes.to_i
  REQUEST_TIMEOUT = 30.freeze

  def initialize
    @client_id = ENV["CASHFREE_CLIENT_ID"].to_s
    @client_secret = ENV["CASHFREE_CLIENT_SECRET"].to_s
    @webhook_secret = ENV["CASHFREE_WEBHOOK_SECRET"].presence || @client_secret
    @pg_base_url = ENV["CASHFREE_BASE_URL"].presence || "https://sandbox.cashfree.com/pg"
    @payout_base_url = ENV["CASHFREE_PAYOUT_BASE_URL"].presence || "https://payout-sandbox.cashfree.com/payout"
    @frontend_url = ENV["FRONTEND_URL"].presence || "http://localhost:5173"
  end

  def configured?
    @client_id.present? && @client_secret.present?
  end

  def payout_configured?
    configured? && ENV["CASHFREE_PAYOUT_CLIENT_ID"].present? && ENV["CASHFREE_PAYOUT_CLIENT_SECRET"].present?
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

  def create_refund(order_reference:, refund_id:, amount:, note:, refund_speed: "STANDARD")
    raise StandardError, "Cashfree is not configured" unless configured?
    raise StandardError, "Cashfree order reference is missing" if order_reference.blank?

    response = self.class.post(
      "#{@pg_base_url}/orders/#{order_reference}/refunds",
      headers: pg_headers,
      body: {
        refund_amount: amount.to_f.round(2),
        refund_id: refund_id,
        refund_note: note,
        refund_speed: refund_speed
      }.to_json,
      timeout: REQUEST_TIMEOUT
    )

    parsed = parse_response(response)
    payload = parsed.is_a?(Array) ? parsed.first : parsed
    if response.success? && payload.present?
      payload
    else
      raise StandardError, payload["message"].presence || payload["error"] || "Unable to initiate Cashfree refund"
    end
  rescue => e
    raise StandardError, "Cashfree Refund Error: #{e.message}"
  end

  def fetch_refund(order_reference:, refund_id:)
    raise StandardError, "Cashfree is not configured" unless configured?
    raise StandardError, "Cashfree order reference is missing" if order_reference.blank?
    raise StandardError, "Refund ID is missing" if refund_id.blank?

    response = self.class.get(
      "#{@pg_base_url}/orders/#{order_reference}/refunds/#{refund_id}",
      headers: pg_headers,
      timeout: REQUEST_TIMEOUT
    )

    parse_response(response)
  rescue => e
    raise StandardError, "Cashfree Refund Status Error: #{e.message}"
  end

  # Payout APIs

  def add_beneficiary(dealer:, idempotency_key:)
    raise StandardError, "Cashfree payout is not configured" unless payout_configured?
    raise StandardError, "Dealer missing required information" unless dealer_onboarding_valid?(dealer)

    response = self.class.post(
      "#{@payout_base_url}/beneficiary/add",
      headers: payout_headers.merge({ "idempotency-key" => idempotency_key }),
      body: {
        beneId: beneficiary_id_for(dealer),
        name: dealer.full_name.presence || dealer.dealer_profile&.business_name,
        email: dealer.email,
        phone: format_phone(dealer.phone),
        bankAccount: dealer.dealer_profile.bank_account_number,
        ifsc: dealer.dealer_profile.ifsc_code,
        bankName: dealer.dealer_profile.bank_name
      }.to_json,
      timeout: REQUEST_TIMEOUT
    )

    parsed = parse_response(response)
    if response.success? && parsed["subCode"] == "200"
      parsed
    else
      raise StandardError, parsed["message"].presence || "Unable to add beneficiary for seller onboarding"
    end
  rescue => e
    raise StandardError, "Cashfree Beneficiary Add Error: #{e.message}"
  end

  def get_beneficiary(dealer:)
    raise StandardError, "Cashfree payout is not configured" unless payout_configured?
    raise StandardError, "Dealer ID is missing" if dealer.blank?

    response = self.class.get(
      "#{@payout_base_url}/beneficiary/#{beneficiary_id_for(dealer)}",
      headers: payout_headers,
      timeout: REQUEST_TIMEOUT
    )

    parse_response(response)
  rescue => e
    raise StandardError, "Cashfree Beneficiary Get Error: #{e.message}"
  end

  def request_transfer(dealer:, amount:, transfer_id:, idempotency_key:)
    raise StandardError, "Cashfree payout is not configured" unless payout_configured?
    raise StandardError, "Transfer amount must be greater than 0" unless amount.to_f > 0

    response = self.class.post(
      "#{@payout_base_url}/requestTransfer",
      headers: payout_headers.merge({ "idempotency-key" => idempotency_key }),
      body: {
        beneId: beneficiary_id_for(dealer),
        amount: amount.to_f.round(2),
        transferId: transfer_id,
        transferMode: "NEFT",
        remarks: "Seller payout - #{transfer_id}"
      }.to_json,
      timeout: REQUEST_TIMEOUT
    )

    parsed = parse_response(response)
    if response.success? && parsed["subCode"] == "200"
      parsed
    else
      raise StandardError, parsed["message"].presence || "Unable to request transfer"
    end
  rescue => e
    raise StandardError, "Cashfree Transfer Request Error: #{e.message}"
  end

  def get_transfer_status(transfer_id:)
    raise StandardError, "Cashfree payout is not configured" unless payout_configured?
    raise StandardError, "Transfer ID is missing" if transfer_id.blank?

    response = self.class.get(
      "#{@payout_base_url}/getTransferStatus",
      query: { transferId: transfer_id },
      headers: payout_headers,
      timeout: REQUEST_TIMEOUT
    )

    parse_response(response)
  rescue => e
    raise StandardError, "Cashfree Transfer Status Error: #{e.message}"
  end

  def verify_webhook_signature!(raw_body:, signature:, timestamp:)
    raise StandardError, "Cashfree webhook secret is not configured" if @webhook_secret.blank?
    raise StandardError, "Missing webhook signature" if signature.blank?
    raise StandardError, "Missing webhook timestamp" if timestamp.blank?

    timestamp_value = timestamp.to_i
    raise StandardError, "Invalid webhook timestamp" if timestamp_value <= 0
    raise StandardError, "Webhook timestamp is outside the allowed tolerance" if (Time.current.to_i - timestamp_value).abs > WEBHOOK_TOLERANCE_SECONDS

    computed_signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest("sha256", @webhook_secret, "#{timestamp}#{raw_body}")
    )

    unless ActiveSupport::SecurityUtils.secure_compare(computed_signature, signature.to_s)
      raise StandardError, "Invalid webhook signature"
    end

    true
  end

  private

  def pg_headers
    {
      "Content-Type" => "application/json",
      "x-api-version" => ENV["CASHFREE_API_VERSION"].presence || DEFAULT_API_VERSION,
      "x-client-id" => @client_id,
      "x-client-secret" => @client_secret
    }
  end

  def payout_headers
    {
      "Content-Type" => "application/json",
      "x-api-version" => PAYOUT_API_VERSION,
      "x-client-id" => ENV["CASHFREE_PAYOUT_CLIENT_ID"].to_s,
      "x-client-secret" => ENV["CASHFREE_PAYOUT_CLIENT_SECRET"].to_s
    }
  end

  def beneficiary_id_for(dealer)
    "DEAL-#{dealer.id}-#{dealer.account_id}" 
  end

  def format_phone(phone)
    phone.to_s.gsub(/\D/, "").last(10).presence || "9999999999"
  end

  def dealer_onboarding_valid?(dealer)
    profile = dealer.dealer_profile
    dealer.present? && 
    dealer.email.present? &&
    dealer.phone.present? &&
    profile&.bank_account_number.present? &&
    profile&.ifsc_code.present? &&
    profile&.bank_name.present?
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
      customer_email: customer.try(:email).presence || "support@salespoints.in",
      customer_phone: safe_phone
    }
  end

  def parse_response(response)
    body = response.respond_to?(:parsed_response) ? response.parsed_response : response
    body.is_a?(Hash) ? body : {}
  end
end
