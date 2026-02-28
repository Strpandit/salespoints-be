class CreateProductSpecifications < ActiveRecord::Migration[8.0]
  def change
    create_table :product_specifications do |t|
      t.references :product, null: false, foreign_key: true
      t.string :key
      t.string :value

      t.timestamps
    end
  end
end
