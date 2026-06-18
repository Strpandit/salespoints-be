class B2bOrder < ApplicationRecord
  belongs_to :buyer_dealer, class_name: "Dealer"
  belongs_to :seller_dealer, class_name: "Dealer", optional: true
  belongs_to :buyer_payment_attempt, class_name: "PaymentAttempt", optional: true
  has_many :b2b_order_items, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy
  has_many :b2b_order_offers, dependent: :destroy

  STATUSES = %w[pending partially_accepted accepted cancelled].freeze
  PAYMENT_METHODS = %w[cod online].freeze
  PAYMENT_STATUSES = %w[pending paid failed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :requested_radius_km, numericality: { greater_than: 0 }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }

  scope :pending, -> { where(status: "pending") }

  def recalculate_totals!
    priced_items = b2b_order_items.accepted_items.includes(product_variant: :product)

    self.subtotal_amount = priced_items.sum(&:total_price).to_d
    self.tax_amount = priced_items.sum do |item|
      item.product_variant&.tax_amount_from_inclusive(item.total_price) || 0.to_d
    end
    self.total_amount = subtotal_amount.to_d - discount_amount.to_d
    save!
  end

  def refresh_status!
    accepted_count = b2b_order_items.accepted_items.count
    open_count = b2b_order_items.open_items.count

    next_status =
      if accepted_count.zero?
        "pending"
      elsif open_count.zero?
        "accepted"
      else
        "partially_accepted"
      end

    attrs = { status: next_status }
    attrs[:accepted_at] = Time.current if next_status == "accepted" && accepted_at.blank?
    update!(attrs)
  end

  def expire_open_offers!
    b2b_order_offers.open_state.where.not(expires_at: nil).where("expires_at <= ?", Time.current).find_each do |offer|
      offer.update!(status: "expired", responded_at: Time.current)
    end
  end
end
