class PaymentGatewayWebhookEvent < ApplicationRecord
  PROVIDERS = %w[cashfree].freeze
  STATUSES = %w[received processing processed ignored rejected failed].freeze

  validates :provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }
  validates :event_id, :payload_digest, :received_at, presence: true
  validates :event_id, uniqueness: { scope: :provider }

  scope :recent, -> { order(received_at: :desc) }

  def processed?
    status == "processed"
  end

  def ignored?
    status == "ignored"
  end

  def failed?
    status == "failed"
  end

  def pending?
    status == "received" || status == "processing"
  end

  def mark_processed!
    update!(status: "processed", processed_at: Time.current)
  end

  def mark_failed!(error_message)
    update!(status: "failed", error_message: error_message, processed_at: Time.current)
  end
end
