class CreateProductVariantColors < ActiveRecord::Migration[8.0]
  def change
    create_table :product_variant_colors do |t|
      t.references :product_variant, null: false, foreign_key: true
      t.string :color_name
      t.string :color_hex
      t.string :sku_code
      t.bigint :primary_media_blob_id

      t.timestamps
    end
  end
end
