class DealerProduct < ApplicationRecord
  belongs_to :dealer
  belongs_to :product
  belongs_to :product_variant

  has_many :cart_items
  has_many :reviews
  # has_many :order_items

  enum :approve_status, { pending: 0, approved: 1, rejected: 2 }

  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :product_variant_id, uniqueness: { scope: :dealer_id }

  scope :live, -> { where(is_active: true, approve_status: 1).where("stock_quantity > 0") }
  
  def ranking_score
    price_score = 1.0 / (product_variant.dealer_selling_price.to_f + 1)

    rating_score = reviews.average(:rating).to_f

    stock_score = stock_quantity > 0 ? 1 : 0

    (price_score * 50) +
    (rating_score * 30) +
    (stock_score * 20)
  end
end
