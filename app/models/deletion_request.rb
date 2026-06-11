class DeletionRequest < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :requestable, polymorphic: true

  belongs_to :reviewed_by_admin, class_name: "AdminUser", optional: true

  validates :status, inclusion: { in: STATUSES }

  validates :requested_at, presence: true

  scope :pending, -> { where(status: "pending") }

  scope :approved, -> { where(status: "approved") }

  scope :rejected, -> { where(status: "rejected") }

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end
end
