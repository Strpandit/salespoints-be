class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :dealer_product
  belongs_to :product_variant

  validates :quantity, numericality: { greater_than: 0 }
  validates :product_variant_id, uniqueness: { scope: [:cart_id, :dealer_product_id], message: "already in cart" }

  before_validation :set_unit_price, if: :unit_price_blank?
  before_save :set_total_price

  validate :stock_available
  validate :dealer_cannot_buy_own_product

  def unit_price_blank?
    unit_price.blank? || unit_price.zero?
  end

  def set_unit_price
    pricing = Pricing::PriceCalculator.new(
      variant: product_variant,
      quantity: 1,
      user_type: cart.dealer? ? :dealer : :account
    ).call

    self.unit_price = pricing[:unit_price]
  end

  def set_total_price
    pricing = Pricing::PriceCalculator.new(
      variant: product_variant,
      quantity: quantity,
      user_type: cart.dealer? ? :dealer : :account
    ).call

    self.unit_price = pricing[:unit_price]
    self.total_price = pricing[:subtotal]
  end

  def stock_available
    return unless dealer_product

    if quantity > dealer_product.stock_quantity
      errors.add(:quantity, "exceeds available stock")
    end
  end

  def dealer_cannot_buy_own_product
    return unless cart.dealer?

    if cart.buyer_id == dealer_product.dealer_id
      errors.add(:base, "Dealer cannot buy their own product")
    end
  end
end
