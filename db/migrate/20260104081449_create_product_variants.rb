class CreateProductVariants < ActiveRecord::Migration[8.0]
  def change
    create_table :product_variants do |t|
      t.references :product, null: false, foreign_key: true
      t.string :variant_sku
      t.decimal :price, precision: 10, scale: 2, null: false
      t.decimal :selling_price, precision: 10, scale: 2
      t.decimal :dealer_price, precision: 10, scale: 2, null: false
      t.decimal :dealer_selling_price, precision: 10, scale: 2
      t.integer :discount_percentage, default: 0
      t.boolean :is_active, default: true
      t.string :attributes, default: '{}'
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :product_variants, :variant_sku, unique: true
  end
end
