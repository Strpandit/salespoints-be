class AddColorsToProductVariants < ActiveRecord::Migration[8.0]
  def change
    add_column :product_variants, :colors, :string, array: true
  end
end
