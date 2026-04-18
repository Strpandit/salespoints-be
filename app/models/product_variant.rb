class ProductVariant < ApplicationRecord
  belongs_to :product
  has_many :dealer_products
  has_many :cart_items
  has_many :order_items

  validates :variant_sku, presence: true, uniqueness: true
  validates :selling_price, :dealer_selling_price, presence: true, numericality: true

  scope :active, -> { where(is_active: true, deleted_at: nil) }

  before_save :calculate_discount_percentage

  def calculate_discount_percentage
    if selling_price.present? && price.present? && price > selling_price
      self.discount_percentage = (((price - selling_price) / price.to_f) * 100).round
    else
      self.discount_percentage = 0
    end
  end

  # def destroy
  #   if order_items.exists?
  #     errors.add(:base, "Cannot delete variant tied to orders.")
  #     throw(:abort)
  #   else
  #     update(deleted_at: Time.current)
  #   end
  # end

  def deleted?
    !!deleted_at
  end

  def sellable?
    is_active && !deleted?
  end
end
