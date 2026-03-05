class WholesalerPost < ApplicationRecord
  belongs_to :dealer
  belongs_to :dealer_product, optional: true

  validates :title, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }

end
