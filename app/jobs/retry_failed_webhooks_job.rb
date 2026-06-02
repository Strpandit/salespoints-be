# Create this job for retrying failed webhooks
class RetryFailedWebhooksJob
  include Sidekiq::Job

  sidekiq_options retry: 3

  def perform
    # Find payment gateway webhook events that failed and are within retry window
    failed_events = PaymentGatewayWebhookEvent
      .where(status: "failed")
      .where("created_at > ?", 24.hours.ago)
      .where("attempts < 3")
      .order(created_at: :asc)
      .limit(10)

    processed = 0

    failed_events.each do |event|
      begin
        # Reprocess the event
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
