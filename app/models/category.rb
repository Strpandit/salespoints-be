class Category < ApplicationRecord
  has_many :products, dependent: :nullify
  has_many :cat_filters
  has_many :brand_categories, dependent: :destroy
  has_many :brands, through: :brand_categories
  
  has_one_attached :cat_icon

  validates :name, :slug, presence: true, uniqueness: true

  before_validation :set_slug, on: [:create, :update]

  before_destroy :check_for_products

  validate :acceptable_image

  def check_for_products
    if products.exists?
      errors.add(:base, "Cannot delete category with products.")
      throw(:abort)
    end
  end

  def to_param
    slug
  end

  private

  def set_slug
    self.slug = name.to_s.parameterize if name.present?
  end


  def acceptable_image
    return unless cat_icon.attached?

    unless cat_icon.blob.byte_size <= 2.megabyte
      errors.add(:cat_icon, "is too big")
    end

    accepted_types = ["image/jpeg", "image/png", "image/jpg"]

    unless accepted_types.include?(cat_icon.content_type)
      errors.add(:cat_icon, "must be JPEG, JPG or PNG")
    end
  end
end
