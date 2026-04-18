class DealerDeletionRequest < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :dealer
  belongs_to :reviewed_by_admin, class_name: "AdminUser", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :requested_at, presence: true

  scope :pending, -> { where(status: "pending") }
end
