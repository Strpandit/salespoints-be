class ReturnRequest < ApplicationRecord
  REQUEST_TYPES = %w[return replacement].freeze
  REPLACEMENT_MODES = %w[full partial].freeze
  STATUSES = %w[requested partially_replacement_requested approved rejected in_transit received completed cancelled].freeze
  ACTIVE_STATUSES = %w[requested partially_replacement_requested approved in_transit received].freeze

  belongs_to :requestable, polymorphic: true
  belongs_to :requester, polymorphic: true
  has_many :dealer_ledger_entries, dependent: :nullify
  has_many_attached :media

  validates :request_type, inclusion: { in: REQUEST_TYPES }
  validates :replacement_mode, inclusion: { in: REPLACEMENT_MODES }, allow_blank: true
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

  def partial_replacement?
    replacement_mode == "partial"
  end

  def full_replacement?
    replacement_mode == "full" || replacement_mode.blank?
  end

  def b2b_order?
    requestable.is_a?(B2bOrder)
  end

  def retail_order?
    requestable.is_a?(Order)
  end
end
