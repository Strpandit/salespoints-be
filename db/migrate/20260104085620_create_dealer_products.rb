class CreateDealerProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :dealer_products do |t|
      t.references :dealer, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.references :product_variant, null: false, foreign_key: true
      t.integer :stock_quantity
      t.integer :approve_status, default: 0
      t.boolean :is_active, default: true

      t.timestamps
    end
    add_index :dealer_products, :approve_status
  end
end
