class OrderBroadcastTracker < ApplicationRecord
  STATUSES = %w[pending accepted rejected expired].freeze

  belongs_to :order
  belongs_to :dealer

  validates :status, inclusion: { in: STATUSES }
  validates :order_id, uniqueness: { scope: :dealer_id }

  scope :pending, -> { where(status: "pending") }
  scope :accepted, -> { where(status: "accepted") }
  scope :rejected, -> { where(status: "rejected") }
  scope :expired, -> { where(status: "expired") }
  scope :for_order, ->(order_id) { where(order_id: order_id) }
  scope :for_dealer, ->(dealer_id) { where(dealer_id: dealer_id) }

  def open?
    pending?
  end

  def closed?
    accepted? || rejected? || expired?
  end

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
    update!(status: "accepted")
  end

  def mark_rejected!
    update!(status: "rejected")
  end

  def mark_expired!
    update!(status: "expired")
  end
end