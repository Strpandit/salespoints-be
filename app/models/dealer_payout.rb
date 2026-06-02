class DealerPayout < ApplicationRecord
  STATUSES = %w[pending approved processing paid rejected failed cancelled].freeze

  belongs_to :dealer
  belongs_to :approved_by_admin, class_name: "AdminUser", optional: true
  belongs_to :processed_by_admin, class_name: "AdminUser", optional: true

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
