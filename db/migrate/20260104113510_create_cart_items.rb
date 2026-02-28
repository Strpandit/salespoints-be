class CreateCartItems < ActiveRecord::Migration[8.0]
  def change
    create_table :cart_items do |t|
      t.references :cart, null: false, foreign_key: true
      t.references :dealer_product, null: false, foreign_key: true
      t.integer :quantity
      t.decimal :total_price,  precision: 10, scale: 2, null: false

      t.timestamps
    end

    add_index :cart_items, [:cart_id, :dealer_product_id], unique: true, name: 'index_cart_items_uniqueness'
  end
end
