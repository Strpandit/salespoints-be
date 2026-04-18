class PaymentAttempt < ApplicationRecord
  belongs_to :buyer, polymorphic: true

  STATUSES = %w[pending paid failed cancelled processed].freeze

  validates :attempt_number, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :payment_gateway, presence: true

  before_validation :assign_attempt_number, on: :create

  scope :recent, -> { order(created_at: :desc) }

  def paid?
    status == "paid"
  end

  def processed?
    status == "processed"
  end

  def terminal?
    %w[processed failed cancelled].include?(status)
  end

  private

  def assign_attempt_number
    return if attempt_number.present?

    loop do
      candidate = "PAY#{Time.current.strftime('%y%m%d')}#{SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')}"
      unless self.class.exists?(attempt_number: candidate)
        self.attempt_number = candidate
        break
      end
    end
  end
end
