class Product < ApplicationRecord
  include AttachableMediaValidations
  include PrimaryMediaAttachable

  belongs_to :category
  belongs_to :brand
  has_many_attached :media

  has_many :product_variants, dependent: :destroy, inverse_of: :product
  has_many :product_specifications, dependent: :destroy, inverse_of: :product
  has_many :dealer_products
  has_many :reviews, dependent: :destroy

  accepts_nested_attributes_for :product_specifications, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :product_variants, allow_destroy: true, reject_if: :reject_blank_product_variant?

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

  def deleted?
    !!deleted_at
  end

  def sellable?
    return false if deleted?
    return true if has_price? && product_variants.active.none?
    product_variants.active.any? { |v| v.sellable? }
  end

  def ensure_default_variant!
    existing = product_variants.first
    return existing if existing

    return nil unless has_price?

    product_variants.create!(
      variant_sku: "#{sku}-DEFAULT",
      price: product_attribute_value(:price),
      selling_price: product_attribute_value(:selling_price),
      dealer_price: product_attribute_value(:dealer_price),
      dealer_selling_price: product_attribute_value(:dealer_selling_price),
      discount_percentage: product_attribute_value(:discount_percentage) || 0,
      is_active: true
    )
  end

  def has_price?
    product_attribute_value(:price).present? ||
      product_attribute_value(:selling_price).present? ||
      product_attribute_value(:dealer_price).present? ||
      product_attribute_value(:dealer_selling_price).present?
  end

  def has_variant_prices?
    product_variants.active.exists?(
      "price IS NOT NULL OR selling_price IS NOT NULL OR dealer_price IS NOT NULL OR dealer_selling_price IS NOT NULL"
    )
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

  def reject_blank_product_variant?(attributes)
    attrs = attributes.to_h.stringify_keys.except("_destroy", "id", "is_active")
    media = Array(attrs.delete("media")).reject(&:blank?)
    variant_attrs = attrs.delete("variant_attributes")

    attrs.values.all?(&:blank?) &&
      media.empty? &&
      blank_variant_attributes?(variant_attrs)
  end

  def blank_variant_attributes?(value)
    case value
    when nil
      true
    when Array
      value.all? do |entry|
        if entry.respond_to?(:to_h)
          entry.to_h.values.all?(&:blank?)
        else
          entry.blank?
        end
      end
    when Hash
      value.values.all?(&:blank?)
    else
      value.blank?
    end
  end

  def product_attribute_value(name)
    return self[name] if has_attribute?(name)
    return public_send(name) if respond_to?(name)

    nil
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
