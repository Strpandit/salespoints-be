class CashfreeWebhookProcessingService
  def initialize(headers:, raw_body:)
    @headers = normalize_headers(headers)
    @raw_body = raw_body.to_s
  end

  def call
    Rails.logger.info "=== Cashfree Webhook Received ==="
    Rails.logger.info "Headers: #{@headers.inspect}"
    Rails.logger.info "Raw Body: #{@raw_body[0..200]}..."

    verify_signature!
    payload = parse_payload!
    event = find_or_create_event!(payload)

    return event if event.processed? || event.ignored?

    event.update!(status: "processing")
    process_payload!(payload)
    event.update!(status: "processed", processed_at: Time.current, response_code: 200, payload: payload)
    event
  rescue StandardError => e
    @event&.update!(
      status: failure_status_for(e),
      error_message: e.message,
      response_code: response_code_for(e),
      payload: @parsed_payload || {}
    )
    raise
  end

  private

  attr_reader :headers, :raw_body

  def verify_signature!

    signature = headers["x-webhook-signature"]
    timestamp = headers["x-webhook-timestamp"]

    Rails.logger.info "Signature: #{signature}"
    Rails.logger.info "Timestamp: #{timestamp}"

    if signature.blank?
      Rails.logger.warn "Missing webhook signature"
      raise StandardError, "Missing webhook signature"
    end

    if timestamp.blank?
      Rails.logger.warn "Missing webhook timestamp"
      raise StandardError, "Missing webhook timestamp"
    end

    CashfreeService.new.verify_webhook_signature!(
      raw_body: raw_body,
      signature: signature,
      timestamp: timestamp
      # signature: headers["x-webhook-signature"],
      # timestamp: headers["x-webhook-timestamp"]
    )
  rescue StandardError => e
    Rails.logger.error "Signature verification failed: #{e.message}"
    raise StandardError, "Invalid webhook signature: #{e.message}"
  end

  def parse_payload!
    @parsed_payload = JSON.parse(raw_body)
  rescue JSON::ParserError
    raise StandardError, "Invalid webhook payload"
  end

  def find_or_create_event!(payload)
    @event = PaymentGatewayWebhookEvent.find_or_initialize_by(
      provider: "cashfree",
      event_id: event_id_for(payload)
    )

    if @event.persisted?
      @event
    else
      @event.assign_attributes(
        event_type: event_type_for(payload),
        payload_digest: Digest::SHA256.hexdigest(raw_body),
        status: "received",
        received_at: Time.current,
        headers: headers.slice("x-webhook-signature", "x-webhook-timestamp", "x-api-version", "user-agent"),
        payload: payload
      )
      @event.save!
      @event
    end
  end

  def process_payload!(payload)
    order_ref = payload.dig("data", "order", "order_id") || payload["order_id"]
    payment_status = payload.dig("data", "payment", "payment_status").to_s.upcase

    raise StandardError, "Cashfree order reference missing in webhook" if order_ref.blank?

    attempt = PaymentAttempt.find_by(attempt_number: order_ref) || PaymentAttempt.find_by(gateway_order_reference: order_ref)
    return process_payment_attempt!(attempt, payload, payment_status) if attempt.present?

    order = Order.find_by(order_number: order_ref) || Order.find_by(gateway_order_reference: order_ref)
    return @event.update!(status: "ignored", processed_at: Time.current, response_code: 200) if order.blank?

    process_order!(order, payload, payment_status)
  end

  def process_payment_attempt!(attempt, payload, payment_status)
    if payment_status == "SUCCESS"
      return if attempt.processed?

      attempt.update!(
        status: "paid",
        paid_at: attempt.paid_at || Time.current,
        payment_reference: payload.dig("data", "payment", "cf_payment_id") || attempt.payment_reference,
        payment_gateway_payload: attempt.payment_gateway_payload.merge(payload)
      )
      finalization = PaymentAttemptFinalizationService.new(payment_attempt: attempt).call
      finalization.orders.each do |order|
        OrderNotificationJob.perform_later(order.id, "placed", attempt.buyer_type, attempt.buyer_id)
        OrderNotificationJob.perform_later(order.id, "payment_paid", attempt.buyer_type, attempt.buyer_id)
      end
    elsif payment_status.present?
      terminal_state = payment_status.in?(%w[CANCELLED USER_DROPPED]) ? "cancelled" : "failed"
      attempt.update!(
        status: attempt.terminal? ? attempt.status : terminal_state,
        payment_gateway_payload: attempt.payment_gateway_payload.merge(payload),
        failure_reason: payment_status,
        cancelled_at: terminal_state == "cancelled" ? (attempt.cancelled_at || Time.current) : attempt.cancelled_at,
        failed_at: terminal_state == "failed" ? (attempt.failed_at || Time.current) : attempt.failed_at
      )
    end
  end

  def process_order!(order, payload, payment_status)
    if payment_status == "SUCCESS"
      order.mark_payment_paid!(
        reference: payload.dig("data", "payment", "cf_payment_id"),
        gateway_payload: payload
      )
      OrderNotificationJob.perform_later(order.id, "payment_paid")
    elsif payment_status.present?
      order.mark_payment_failed!(gateway_payload: payload)
    end
  end

  def normalize_headers(raw_headers)
    raw_headers.to_h.each_with_object({}) do |(key, value), memo|
      original = key.to_s
      memo[original.downcase] = value

      normalized = original.sub(/\AHTTP_/, "").tr("_", "-").downcase
      memo[normalized] = value if normalized.present?
    end
  end

  def event_id_for(payload)
    data = payload["data"] || {}
    order_id = data.dig("order", "order_id") || payload["order_id"]
    payment = data["payment"] || {}
    refund = data["refund"] || {}
    candidate = [
      payload["type"],
      payment["cf_payment_id"],
      refund["cf_refund_id"] || refund["refund_id"],
      payment["payment_status"] || refund["refund_status"],
      order_id
    ].compact.join(":")

    candidate.presence || Digest::SHA256.hexdigest(raw_body)
  end

  def event_type_for(payload)
    payload["type"] || payload.dig("data", "payment", "payment_status") || payload.dig("data", "refund", "refund_status") || "cashfree_event"
  end

  def failure_status_for(error)
    if error.message.match?(/signature|timestamp/i)
      "rejected"
    else
      "failed"
    end
  end

  def response_code_for(error)
    error.message.match?(/signature|timestamp/i) ? 401 : 422
  end
end
