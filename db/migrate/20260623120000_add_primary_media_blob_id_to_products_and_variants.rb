class AddPrimaryMediaBlobIdToProductsAndVariants < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :primary_media_blob_id, :bigint
    add_column :products, :stock_quantity, :integer, default: 1
    add_index :products, :primary_media_blob_id

    add_column :product_variants, :primary_media_blob_id, :bigint
    add_index :product_variants, :primary_media_blob_id
  end
end
