class PaymentGatewayWebhookEvent < ApplicationRecord
  PROVIDERS = %w[cashfree].freeze
  STATUSES = %w[received processing processed ignored rejected failed].freeze

  validates :provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }
  validates :event_id, :payload_digest, :received_at, presence: true
  validates :event_id, uniqueness: { scope: :provider }

  scope :recent, -> { order(received_at: :desc) }
end
