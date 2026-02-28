class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :dealer_product

  validates :quantity, numericality: { greater_than: 0 }

  validate :stock_available

  def stock_available
    if quantity > dealer_product.stock_quantity
      errors.add(:quantity, "exceeds available stock")
    end
  end
end
