class CreateBrandCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :brand_categories do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true

      t.timestamps
    end

    add_index :brand_categories, [:brand_id, :category_id], unique: true
  end
end
