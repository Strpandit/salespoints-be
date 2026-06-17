class Product < ApplicationRecord
  include AttachableMediaValidations

  belongs_to :category
  belongs_to :brand
  has_many_attached :media

  has_many :product_variants, dependent: :destroy, inverse_of: :product
  has_many :product_specifications, dependent: :destroy, inverse_of: :product
  has_many :dealer_products

  accepts_nested_attributes_for :product_specifications, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :product_variants, allow_destroy: true, reject_if: :all_blank

  validates :name, :slug, :sku, presence: true
  validates :slug, :sku, uniqueness: true
  validate :catalog_media_presence
  validate :media_files_valid
  validate :brand_category_relation

  scope :featured, -> { where(is_featured: true) }
  scope :new_arrivals, -> { where('created_at >= ?', 15.days.ago) } 
  scope :active, -> { where(is_active: true, deleted_at: nil) }

  before_validation :set_slug, on: [:create, :update]

  def to_param
    slug
  end

  # def destroy
  #   if order_items.exists?
  #     errors.add(:base, "Cannot delete a product in existing orders.")
  #     throw(:abort)
  #   else
  #     update(deleted_at: Time.current)
  #   end
  # end

  def deleted?
    !!deleted_at
  end

  def sellable?
    !deleted? && product_variants.active.any? { |v| v.sellable? }
  end

  def has_price?
    price.present? || selling_price.present? || 
    dealer_price.present? || dealer_selling_price.present?
  end

  def has_variant_prices?
    product_variants.active.exists?(
      "price IS NOT NULL OR selling_price IS NOT NULL OR dealer_price IS NOT NULL OR dealer_selling_price IS NOT NULL"
    )
  end

  def best_price
    return price if price.present? && !has_variant_prices?
    product_variants.active.first&.price || price || 0
  end

  def best_selling_price
    return selling_price if selling_price.present? && !has_variant_prices?
    product_variants.active.first&.selling_price || selling_price || 0
  end

  def best_dealer_price
    return dealer_price if dealer_price.present? && !has_variant_prices?
    product_variants.active.first&.dealer_price || dealer_price || 0
  end

  def best_dealer_selling_price
    return dealer_selling_price if dealer_selling_price.present? && !has_variant_prices?
    product_variants.active.first&.dealer_selling_price || dealer_selling_price || 0
  end

  def best_discount_percentage
    return discount_percentage if discount_percentage.present? && !has_variant_prices?
    product_variants.active.first&.discount_percentage || discount_percentage || 0
  end

  def price_source
    return "variant" if has_variant_prices?
    return "product" if has_price?
    "none"
  end
  
  private

  def catalog_media_presence
    return if media.attached? || product_variants.any? { |variant| !variant.marked_for_destruction? && variant.media.attached? }

    errors.add(:base, "Add at least one image or video on the product or one of its variants")
  end

  def media_files_valid
    validate_attachment_set(:media)
  end

  def brand_category_relation
    return if brand.blank? || category.blank?

    unless brand.categories.exists?(id: category_id)
      errors.add(:category, "does not belong to selected brand")
    end
  end

  def set_slug
    self.slug = name.to_s.parameterize if name.present?
  end
end
