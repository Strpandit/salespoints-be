class Cart < ApplicationRecord
  belongs_to :buyer, polymorphic: true
  has_many :cart_items, dependent: :destroy

  def total_amount
    cart_items.sum("quantity * total_price")
  end
end
