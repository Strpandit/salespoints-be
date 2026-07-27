class DealerBroadcastTracker < ApplicationRecord
  belongs_to :dealer
  belongs_to :b2b_order

  STATUSES = %w[pending accepted rejected expired].freeze
  
  validates :b2b_order_id, presence: true
  validates :dealer_id, presence: true
  validates :b2b_order_id, uniqueness: { scope: :dealer_id }
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  scope :pending, -> { where(status: "pending") }
  scope :accepted, -> { where(status: "accepted") }
  scope :rejected, -> { where(status: "rejected") }
  scope :expired, -> { where(status: "expired") }
  scope :for_order, ->(order_id) { where(b2b_order_id: order_id) }
  scope :for_dealer, ->(dealer_id) { where(dealer_id: dealer_id) }

  def pending?
    status == "pending"
  end

  def accepted?
    status == "accepted"
  end

  def rejected?
    status == "rejected"
  end

  def expired?
    status == "expired"
  end

  def mark_accepted!
    return if accepted?
    update!(status: "accepted")
  end

  def mark_rejected!
    return if rejected?
    update!(status: "rejected")
  end

  def mark_expired!
    return if expired?
    update!(status: "expired")
  end
end
