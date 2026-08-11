class DealerProduct < ApplicationRecord
  belongs_to :dealer
  belongs_to :product
  belongs_to :product_variant, optional: true

  has_many :reviews, dependent: :destroy
  has_many :wholesaler_posts, dependent: :destroy

  has_many :order_items, dependent: :nullify
  has_many :b2b_order_items, dependent: :nullify

  enum :approve_status, { pending: 0, approved: 1, rejected: 2 }

  validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :product_variant_id, uniqueness: { scope: :dealer_id }
  validates :sell_in_b2b, inclusion: { in: [true, false] }
  validates :sell_in_b2c, inclusion: { in: [true, false] }
  validate :at_least_one_sales_channel_enabled

  before_save :sync_total_stock_from_colors

  def color_stock_for(color_id)
    return stock_quantity if color_stocks.blank?
    key = color_id.to_s
    return 0 unless color_stocks.key?(key)
    
    val = color_stocks[key]
    val.is_a?(Hash) ? val["stock"].to_i : val.to_i
  end

  def deduct_color_stock!(color_id, quantity)
    qty = quantity.to_i
    key = color_id.to_s
    
    if color_stocks.present? && color_stocks.is_a?(Hash) && color_stocks.any?
      if color_stocks.key?(key)
        val = color_stocks[key]
        current = val.is_a?(Hash) ? val["stock"].to_i : val.to_i
        raise StandardError, "Insufficient stock for selected color" if current < qty
        
        if val.is_a?(Hash)
          color_stocks[key]["stock"] = current - qty
        else
          color_stocks[key] = current - qty
        end
        
        sync_total_stock_from_colors
        save!
      else
        raise StandardError, "Selected color is not in stock for this seller"
      end
    else
      raise StandardError, "Insufficient total stock" if stock_quantity.to_i < qty
      update!(stock_quantity: stock_quantity.to_i - qty)
    end
  end

  scope :with_active_dealer, -> { 
    joins(:dealer).where(dealers: { deleted_at: nil, status: 'active' })
  }
  scope :live, -> { with_active_dealer.where(is_active: true, approve_status: 1).where("dealer_products.stock_quantity > 0 OR dealer_products.stock_quantity IS NULL") }
  scope :for_b2b, -> { where(sell_in_b2b: true) }
  scope :for_b2c, -> { where(sell_in_b2c: true) }
  
  def effective_hsn_code
    return product_variant&.effective_hsn_code if product_variant.present?
    return product&.hsn_code if product.present?
    nil
  end

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

  def sync_total_stock_from_colors
    if color_stocks.present? && color_stocks.is_a?(Hash) && color_stocks.any?
      total = color_stocks.values.sum do |val|
        val.is_a?(Hash) ? val["stock"].to_i : val.to_i
      end
      self.stock_quantity = total
    end
  end

  def at_least_one_sales_channel_enabled
    return if sell_in_b2b? || sell_in_b2c?

    errors.add(:base, "Select at least one sales channel: B2B or B2C")
  end
end
