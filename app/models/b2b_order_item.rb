class B2bOrderItem < ApplicationRecord
  belongs_to :b2b_order
  belongs_to :dealer_product, optional: true
  belongs_to :product_variant
  belongs_to :wholesaler_post, optional: true

  STATUSES = %w[open accepted cancelled].freeze

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, :total_price, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :open_items, -> { where(status: "open") }
  scope :accepted_items, -> { where(status: "accepted") }

  def accepted?
    status == "accepted"
  end
end
