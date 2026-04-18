class Order < ApplicationRecord
  belongs_to :buyer, polymorphic: true
  belongs_to :seller_dealer, class_name: "Dealer", optional: true
  has_many :order_items, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :nullify

  enum :status, {
    pending: "pending",
    processing: "processing",
    shipped: "shipped",
    delivered: "delivered",
    cancelled: "cancelled"
  }

  PAYMENT_METHODS = %w[cod online].freeze
  PAYMENT_STATUSES = %w[pending paid failed refunded].freeze

  validates :order_number, presence: true, uniqueness: true
  validates :buyer_type, :buyer_id, presence: true
  validates :payment_method, :payment_status, presence: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }

  before_validation :assign_order_number, on: :create
  before_validation :set_placed_at, on: :create

  scope :recent, -> { order(created_at: :desc) }

  def total_items
    order_items.sum(:quantity)
  end

  def can_transition_to?(next_status)
    return false if next_status.blank?

    allowed = {
      "pending" => %w[processing cancelled],
      "processing" => %w[shipped cancelled],
      "shipped" => %w[delivered cancelled],
      "delivered" => [],
      "cancelled" => []
    }

    allowed.fetch(status.to_s, []).include?(next_status.to_s)
  end

  def mark_payment_paid!(reference: nil, gateway_payload: {})
    update!(
      payment_status: "paid",
      payment_reference: reference.presence || payment_reference,
      payment_gateway_payload: payment_gateway_payload.merge(gateway_payload || {}),
      payment_confirmed_at: payment_confirmed_at || Time.current
    )
  end

  def mark_payment_failed!(gateway_payload: {})
    update!(
      payment_status: "failed",
      payment_gateway_payload: payment_gateway_payload.merge(gateway_payload || {})
    )
  end

  private

  def assign_order_number
    return if order_number.present?

    loop do
      candidate = "SP#{Time.current.strftime('%y%m%d')}#{SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')}"
      unless self.class.exists?(order_number: candidate)
        self.order_number = candidate
        break
      end
    end
  end

  def set_placed_at
    self.placed_at ||= Time.current
  end
end
