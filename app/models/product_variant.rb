class ProductVariant < ApplicationRecord
  belongs_to :product
  include AttachableMediaValidations

  has_many_attached :media
  has_many :dealer_products
  has_many :cart_items
  has_many :order_items

  validates :variant_sku, presence: true, uniqueness: true
  validates :selling_price, :dealer_selling_price, presence: true, numericality: true
  validate :media_files_valid

  scope :active, -> { where(is_active: true, deleted_at: nil) }

  before_save :calculate_discount_percentage

  def inclusive_price
    product.inclusive_amount(price || 0)
  end

  def inclusive_selling_price
    product.inclusive_amount(selling_price || 0)
  end

  def inclusive_dealer_price
    product.inclusive_amount(dealer_price || 0)
  end

  def inclusive_dealer_selling_price
    product.inclusive_amount(dealer_selling_price || 0)
  end

  def tax_amount_from_inclusive(amount)
    product.tax_amount_from_inclusive(amount)
  end

  def display_media_attachments
    media.attached? ? media : product.media
  end

  def calculate_discount_percentage
    if selling_price.present? && price.present? && price > selling_price
      inclusive_mrp = inclusive_price
      inclusive_selling = inclusive_selling_price
      if inclusive_mrp > inclusive_selling
        self.discount_percentage = (((inclusive_mrp - inclusive_selling) / inclusive_mrp.to_f) * 100).round
      end
    end
  end

  def deleted?
    !!deleted_at
  end

  def sellable?
    is_active && !deleted?
  end

  private

  def media_files_valid
    validate_attachment_set(:media)
  end
end
