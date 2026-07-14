class MakeProductVariantIdNullableInB2bOrderItems < ActiveRecord::Migration[8.0]
  def change
    change_column_null :b2b_order_items, :product_variant_id, true
  end
end
