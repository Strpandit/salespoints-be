class AddColumnToCartItems < ActiveRecord::Migration[8.0]
  def change
    add_reference :cart_items, :product_variant, null: false, foreign_key: true
    add_column :cart_items, :unit_price, :decimal, precision: 10, scale: 2, null: false, default: 0.0
  end
end
