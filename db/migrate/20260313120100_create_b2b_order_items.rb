class CreateB2bOrderItems < ActiveRecord::Migration[8.0]
  def change
    create_table :b2b_order_items do |t|
      t.references :b2b_order, null: false, foreign_key: true
      t.references :dealer_product, foreign_key: true
      t.references :product_variant, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.decimal :unit_price, precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_price, precision: 12, scale: 2, null: false, default: 0

      t.timestamps
    end
  end
end
