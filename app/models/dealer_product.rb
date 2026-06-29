class DealerProduct < ApplicationRecord
  belongs_to :dealer
  belongs_to :product
  belongs_to :product_variant

  has_many :reviews, dependent: :destroy
  has_many :wholesaler_posts, dependent: :destroy

  enum :approve_status, { pending: 0, approved: 1, rejected: 2 }

  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :product_variant_id, uniqueness: { scope: :dealer_id }

  scope :live, -> { where(is_active: true, approve_status: 1).where("stock_quantity > 0") }
  
  def ranking_score
    variant = product_variant
    price = variant.unit_price_for(:dealer)
    price_score = 1.0 / (price + 1)

    rating_score = reviews.average(:rating).to_f

    stock_score = stock_quantity > 0 ? 1 : 0

    (price_score * 50) +
    (rating_score * 30) +
    (stock_score * 20)
  end

  def sellable?
    is_active && approve_status == "approved" && stock_quantity.to_i > 0
  end
  
  def owner?(buyer)
    dealer_id == buyer.id
  end

  def display_media_attachments
    product_variant&.display_media_attachments || product&.media || []
  end
end
