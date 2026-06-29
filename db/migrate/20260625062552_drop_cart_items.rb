class DropCartItems < ActiveRecord::Migration[8.0]
  def up
    drop_table :cart_items
    drop_table :carts

    remove_foreign_key :order_items, :dealer_products if foreign_key_exists?(:order_items, :dealer_products)
    remove_index :order_items, :dealer_product_id if index_exists?(:order_items, :dealer_product_id)
    remove_column :order_items, :dealer_product_id if column_exists?(:order_items, :dealer_product_id)
  end

  def down
    add_column :order_items, :dealer_product_id, :bigint
    add_index :order_items, :dealer_product_id
    add_foreign_key :order_items, :dealer_products

    create_table :carts do |t|
      t.string :buyer_type, null: false
      t.integer :buyer_id, null: false
      t.references :coupon

      t.string :coupon_code

      t.timestamps

      t.index [:buyer_type, :buyer_id], unique: true
    end

    create_table :cart_items do |t|
      t.references :cart, null: false
      t.references :dealer_product, null: false
      t.integer :quantity
      t.decimal :total_price, precision: 10, scale: 2, null: false
      t.references :product_variant, null: false
      t.decimal :unit_price, precision: 10, scale: 2, default: 0.0, null: false

      t.timestamps

      t.index [:cart_id, :dealer_product_id, :product_variant_id],
              unique: true,
              name: "index_cart_items_unique"
    end
  end
end