class ReturnRequest < ApplicationRecord
  REQUEST_TYPES = %w[return replacement].freeze
  STATUSES = %w[requested approved rejected in_transit received completed cancelled].freeze
  ACTIVE_STATUSES = %w[requested approved in_transit received].freeze

  belongs_to :order
  belongs_to :requester, polymorphic: true
  has_many :dealer_ledger_entries, dependent: :nullify

  validates :request_type, inclusion: { in: REQUEST_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :refund_amount, :seller_adjustment_amount, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(created_at: :desc) }

  def open?
    status.in?(ACTIVE_STATUSES)
  end

  def return_request?
    request_type == "return"
  end

  def replacement_request?
    request_type == "replacement"
  end
end
