class CreateOrderItems < ActiveRecord::Migration[8.0]
  def change
    create_table :order_items do |t|
      t.bigint :order_id, null: false
      t.bigint :dealer_product_id, null: false
      t.bigint :product_variant_id, null: false
      t.integer :quantity, null: false, default: 1
      t.decimal :unit_price, precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_price, precision: 12, scale: 2, null: false, default: 0

      t.timestamps
    end

    add_index :order_items, :order_id
    add_index :order_items, :dealer_product_id
    add_index :order_items, :product_variant_id
    add_foreign_key :order_items, :orders
    add_foreign_key :order_items, :dealer_products
    add_foreign_key :order_items, :product_variants
  end
end

