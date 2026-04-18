class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :dealer_product
  belongs_to :product_variant

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, :total_price, numericality: { greater_than_or_equal_to: 0 }

  before_validation :assign_total_price

  def product_name
    dealer_product&.product&.name
  end

  def product_name_with_variant
    base = product_name
    sku = product_variant&.variant_sku
    return base if sku.blank?
    return sku if base.blank?

    "#{base} (#{sku})"
  end

  private

  def assign_total_price
    qty = quantity.to_i
    self.total_price = unit_price.to_d * qty
  end
end

