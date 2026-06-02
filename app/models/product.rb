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

  private

  def catalog_media_presence
    return if media.attached? || product_variants.any? { |variant| !variant.marked_for_destruction? && variant.media.attached? }

    errors.add(:base, "Add at least one image or video on the product or one of its variants")
  end

  def media_files_valid
    validate_attachment_set(:media)
  end

  def set_slug
    self.slug = name.to_s.parameterize if name.present?
  end
end
