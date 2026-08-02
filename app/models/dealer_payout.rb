class DealerPayout < ApplicationRecord
  STATUSES = %w[pending approved processing paid rejected failed cancelled].freeze

  belongs_to :dealer
  belongs_to :requestable, polymorphic: true, optional: true
  belongs_to :approved_by_admin, class_name: "AdminUser", optional: true
  belongs_to :processed_by_admin, class_name: "AdminUser", optional: true
  has_one_attached :gst_invoice

  validates :request_number, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { greater_than: 0 }

  before_validation :assign_request_number, on: :create

  scope :recent, -> { order(created_at: :desc) }

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def processing?
    status == "processing"
  end

  def paid?
    status == "paid"
  end

  def order_reference
    requestable.try(:order_number).presence || requestable.try(:reference_number).presence
  end

  def request_flow
    return "b2c" if requestable.is_a?(Order)
    return "wholesale" if requestable.is_a?(B2bOrder) && requestable.source_type == "WholesalerPost"
    return "b2b" if requestable.is_a?(B2bOrder)

    "dealer_balance"
  end

  private

  def assign_request_number
    return if request_number.present?

    loop do
      candidate = "PO#{Time.current.strftime('%y%m%d')}#{SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')}"
      unless self.class.exists?(request_number: candidate)
        self.request_number = candidate
        break
      end
    end
  end
end
