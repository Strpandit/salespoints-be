class RetryFailedWebhooksJob < ApplicationJob
  queue_as :default

  retry_on StandardError, attempts: 3, wait: :exponentially_longer

  def perform
    failed_events = PaymentGatewayWebhookEvent
                      .where(status: "failed")
                      .where("created_at > ?", 24.hours.ago)
                      .where("attempts < 3")
                      .order(created_at: :asc)
                      .limit(10)

    processed = 0

    failed_events.each do |event|
      begin
        processor = EnhancedPaymentWebhookProcessor.new(
          headers: event.headers,
          raw_body: event.payload.to_json
        )
        processor.call

        event.update!(status: "processed", processed_at: Time.current)
        processed += 1
      rescue StandardError => e
        event.increment!(:attempts)
        Rails.logger.error("Failed to retry webhook event #{event.id}: #{e.message}")
      end
    end

    Rails.logger.info("Webhook retry job processed #{processed} failed events")
  end
end