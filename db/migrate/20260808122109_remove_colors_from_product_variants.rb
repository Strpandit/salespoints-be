class RemoveColorsFromProductVariants < ActiveRecord::Migration[8.0]
  def change
    remove_column :product_variants, :colors, :string
  end
end
