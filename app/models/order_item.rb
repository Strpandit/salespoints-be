class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product_variant

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, :total_price, numericality: { greater_than_or_equal_to: 0 }

  before_validation :assign_total_price

  def product_name
    product_variant&.product&.name
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
    return unless product_variant.present?
    pricing = Pricing::PriceCalculator.new(
      variant: product_variant,
      quantity: quantity,
      user_type: order.buyer.is_a?(Dealer) ? :dealer : :account
    ).call

    self.unit_price = pricing[:unit_price]
    self.total_price = pricing[:subtotal]
  end
end

