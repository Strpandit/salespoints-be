class CouponUsage < ApplicationRecord
  belongs_to :coupon

  validates :user_type, presence: true
  validates :user_id, presence: true
  validates :uses_count, numericality: { greater_than_or_equal_to: 0 }
end
