class EnhancedPaymentWebhookProcessor
  MAX_RETRIES = 3
  RETRY_DELAY = 30.seconds

  def initialize(headers:, raw_body:)
    @headers = normalize_headers(headers)
    @raw_body = raw_body.to_s
    @retry_count = 0
  end

  def call
    verify_signature!
    payload = parse_payload!
    event_type = determine_event_type(payload)

    case event_type
    when :payment_success, :payment_failed
      handle_payment_webhook!(payload, event_type)
    when :refund_status
      handle_refund_webhook!(payload)
    when :payout_status
      handle_payout_webhook!(payload)
    else
      Rails.logger.warn("Unknown webhook event type")
      record_webhook_event!(payload, "unknown", "ignored")
    end

    record_webhook_event!(payload, event_type, "processed")
    head :ok
  rescue StandardError => e
    handle_webhook_error!(e, payload)
    raise
  end

  private

  attr_reader :headers, :raw_body

  def verify_signature!
    CashfreeService.new.verify_webhook_signature!(
      raw_body: raw_body,
      signature: headers["x-webhook-signature"],
      timestamp: headers["x-webhook-timestamp"]
    )
  end

  def parse_payload!
    @payload = JSON.parse(raw_body)
  rescue JSON::ParserError
    raise StandardError, "Invalid webhook payload JSON"
  end

  def determine_event_type(payload)
    event_type = payload["type"].to_s.downcase

    case event_type
    when /payment.*success/, /order.*paid/
      :payment_success
    when /payment.*failed/, /payment.*error/
      :payment_failed
    when /refund/
      :refund_status
    when /payout/, /transfer/
      :payout_status
    else
      :unknown
    end
  end

  def handle_payment_webhook!(payload, event_type)
    order_ref = extract_order_reference(payload)
    raise StandardError, "Order reference missing in webhook" if order_ref.blank?

    # Find payment attempt or order
    payment_attempt = PaymentAttempt.find_by(
      attempt_number: order_ref
    ) || PaymentAttempt.find_by(gateway_order_reference: order_ref)

    if payment_attempt.present?
      process_payment_attempt!(payment_attempt, payload, event_type)
    else
      # Try to find by order
      order = Order.find_by(order_number: order_ref) || Order.find_by(gateway_order_reference: order_ref)
      process_order_payment!(order, payload, event_type) if order.present?
    end
  end

  def handle_refund_webhook!(payload)
    order_ref = extract_order_reference(payload)
    refund_id = payload.dig("data", "refund", "refund_id") || payload["refund_id"]

    order = Order.find_by(order_number: order_ref) || Order.find_by(gateway_order_reference: order_ref)
    return if order.blank?

    refund_status = payload.dig("data", "refund", "refund_status")&.upcase

    case refund_status
    when "SUCCESS"
      order.update!(refund_status: "completed", refunded_at: Time.current)
      OrderNotificationJob.perform_later(order.id, "refunded", order.buyer_type, order.buyer_id)
    when "FAILED"
      order.update!(refund_status: "none")
      AdminNotificationService.notify_refund_failure(order, payload)
    end
  end

  def handle_payout_webhook!(payload)
    transfer_id = extract_transfer_id(payload)
    return if transfer_id.blank?

    payout = DealerPayout.find_by(payment_reference: transfer_id)
    return if payout.blank?

    transfer_status = payload.dig("data", "transfer_status")&.upcase

    case transfer_status
    when "SUCCESS"
      payout.update!(
        status: "paid",
        paid_at: Time.current,
        metadata: payout.metadata.merge(webhook_response: payload)
      )
      DealerPayoutNotificationService.status_updated!(payout.reload)
    when "FAILED"
      payout.update!(
        status: "failed",
        metadata: payout.metadata.merge(
          webhook_response: payload,
          failure_reason: payload.dig("data", "failure_reason") || "Transfer failed"
        )
      )
      AdminNotificationService.notify_payout_failure(payout)
    end
  end

  def process_payment_attempt!(attempt, payload, event_type)
    return if attempt.terminal?

    payment_status = extract_payment_status(payload)

    case event_type
    when :payment_success
      finalize_successful_attempt!(attempt, payload)
    when :payment_failed
      finalize_failed_attempt!(attempt, payload)
    end

    attempt.reload
  end

  def process_order_payment!(order, payload, event_type)
    return if order.payment_status != "pending"

    payment_status = extract_payment_status(payload)

    case event_type
    when :payment_success
      order.update!(
        payment_status: "paid",
        status: "processing",
        payment_gateway_payload: order.payment_gateway_payload.merge(payload)
      )
      OrderNotificationJob.perform_later(order.id, "payment_paid", order.buyer_type, order.buyer_id)
    when :payment_failed
      order.update!(
        payment_status: "failed",
        status: "cancelled",
        payment_gateway_payload: order.payment_gateway_payload.merge(payload)
      )
      OrderNotificationJob.perform_later(order.id, "payment_failed", order.buyer_type, order.buyer_id)
    end
  end

  def finalize_successful_attempt!(attempt, payload)
    attempt.update!(
      status: "paid",
      paid_at: attempt.paid_at || Time.current,
      payment_reference: extract_payment_reference(payload),
      payment_gateway_payload: attempt.payment_gateway_payload.merge(payload)
    )

    finalization = PaymentAttemptFinalizationService.new(payment_attempt: attempt).call
    finalization.orders.each do |order|
      OrderNotificationJob.perform_later(order.id, "placed", attempt.buyer_type, attempt.buyer_id)
      OrderNotificationJob.perform_later(order.id, "payment_paid", attempt.buyer_type, attempt.buyer_id)
    end
  end

  def finalize_failed_attempt!(attempt, payload)
    terminal_state = extract_payment_status(payload) == "CANCELLED" ? "cancelled" : "failed"
    attempt.update!(
      status: terminal_state,
      failure_reason: extract_failure_reason(payload),
      payment_gateway_payload: attempt.payment_gateway_payload.merge(payload)
    )
  end

  def extract_order_reference(payload)
    payload.dig("data", "order", "order_id") || 
    payload["order_id"] || 
    payload["reference"]
  end

  def extract_transfer_id(payload)
    payload.dig("data", "transfer_id") || 
    payload["transfer_id"] || 
    payload["transferId"]
  end

  def extract_payment_status(payload)
    (payload.dig("data", "payment", "payment_status") || 
     payload["payment_status"] || 
     payload["order_status"])&.to_s&.upcase
  end

  def extract_payment_reference(payload)
    payload.dig("data", "payment", "cf_payment_id") || 
    payload["cf_payment_id"] || 
    payload["payment_id"]
  end

  def extract_failure_reason(payload)
    payload.dig("data", "payment", "error_message") || 
    payload["error_message"] || 
    payload["error"] || 
    "Payment processing failed"
  end

  def record_webhook_event!(payload, event_type, status)
    event_id = payload.dig("data", "order", "order_id") || 
               payload["order_id"] || 
               payload["transfer_id"] || 
               "WEBHOOK-#{Time.current.to_i}"

    PaymentGatewayWebhookEvent.create!(
      provider: "cashfree",
      event_type: event_type.to_s,
      event_id: event_id,
      payload_digest: Digest::SHA256.hexdigest(raw_body),
      status: status,
      received_at: Time.current,
      processed_at: status == "processed" ? Time.current : nil,
      headers: headers.slice("x-webhook-signature", "x-webhook-timestamp"),
      payload: @payload || {}
    )
  rescue StandardError => e
    Rails.logger.error("Failed to record webhook event: #{e.message}")
  end

  def handle_webhook_error!(error, payload)
    Rails.logger.error("Webhook processing error: #{error.message}\n#{error.backtrace.join("\n")}")

    event_id = payload.dig("data", "order", "order_id") if payload.present?

    PaymentGatewayWebhookEvent.create!(
      provider: "cashfree",
      event_type: "error",
      event_id: event_id || "ERROR-#{Time.current.to_i}",
      payload_digest: Digest::SHA256.hexdigest(raw_body),
      status: "failed",
      error_message: error.message,
      received_at: Time.current,
      headers: headers.slice("x-webhook-signature", "x-webhook-timestamp"),
      payload: payload || {}
    ) if payload.present?
  end

  def normalize_headers(headers)
    headers.each_with_object({}) do |(key, value), hash|
      hash[key.to_s.downcase] = value
    end
  end
end
