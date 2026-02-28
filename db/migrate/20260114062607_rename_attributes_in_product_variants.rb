class RenameAttributesInProductVariants < ActiveRecord::Migration[8.0]
  def change
    rename_column :product_variants, :attributes, :variant_attributes
  end
end
