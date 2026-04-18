class FixCartItemUniqueIndex < ActiveRecord::Migration[8.0]
  def change
    remove_index :cart_items, name: "index_cart_items_uniqueness"

    add_index :cart_items,
      [:cart_id, :dealer_product_id, :product_variant_id],
      unique: true,
      name: "index_cart_items_unique"
  end
end
