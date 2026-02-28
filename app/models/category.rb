class Category < ApplicationRecord
  has_many :products, dependent: :nullify
  has_many :cat_filters

  validates :name, :slug, presence: true, uniqueness: true

  before_validation :set_slug, on: [:create, :update]

  before_destroy :check_for_products

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
end
