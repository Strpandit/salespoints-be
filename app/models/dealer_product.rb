class DealerProduct < ApplicationRecord
  belongs_to :dealer
  belongs_to :product
  belongs_to :product_variant, optional: true

  has_many :reviews, dependent: :destroy
  has_many :wholesaler_posts, dependent: :destroy

  enum :approve_status, { pending: 0, approved: 1, rejected: 2 }

  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :product_variant_id, uniqueness: { scope: :dealer_id }
  validates :sell_in_b2b, inclusion: { in: [true, false] }
  validates :sell_in_b2c, inclusion: { in: [true, false] }
  validate :at_least_one_sales_channel_enabled

  scope :with_active_dealer, -> { 
    joins(:dealer).where(dealers: { deleted_at: nil, status: 'active' })
  }
  scope :live, -> { with_active_dealer.where(is_active: true, approve_status: 1).where("dealer_products.stock_quantity > 0 OR dealer_products.stock_quantity IS NULL") }
  scope :for_b2b, -> { where(sell_in_b2b: true) }
  scope :for_b2c, -> { where(sell_in_b2c: true) }
  
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

  def sellable_in_b2b?
    sellable? && sell_in_b2b?
  end

  def sellable_in_b2c?
    sellable? && sell_in_b2c?
  end
  
  def owner?(buyer)
    dealer_id == buyer.id
  end

  def display_media_attachments
    return product_variant.display_media_attachments if product_variant.present?
    return product.ordered_media_attachments.map(&:blob) if product&.media&.attached?

    []
  end

  def display_primary_blob_id
    if product_variant.present?
      product_variant.display_primary_blob_id
    else
      product.primary_media_blob_id
    end
  end

  private

  def at_least_one_sales_channel_enabled
    return if sell_in_b2b? || sell_in_b2c?

    errors.add(:base, "Select at least one sales channel: B2B or B2C")
  end
end
