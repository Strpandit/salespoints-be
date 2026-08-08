class AddProductVariantColorToOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_reference :order_items, :product_variant_color, foreign_key: true
    add_reference :b2b_order_items, :product_variant_color, foreign_key: true
    add_column :wholesaler_posts, :ad_hoc_color, :string
  end
end
