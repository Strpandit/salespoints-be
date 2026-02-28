class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.string :name
      t.string :slug
      t.string :sku
      t.text :desc
      t.string :material
      t.string :features, default: '[]'
      t.string :care_instructions, default: '[]'
      t.references :brand, foreign_key: true
      t.boolean :is_featured, default: false
      t.boolean :is_new, default: false
      t.boolean :is_active, default: true
      t.references :category, null: false, foreign_key: true
      t.decimal :tax_rate, precision: 5, scale: 2, default: 0.0, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :products, :slug, unique: true
    add_index :products, :sku, unique: true
    add_index :products, :is_featured
  end
end
