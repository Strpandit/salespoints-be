class AddDealerProductIdToOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_column :order_items, :dealer_product_id, :integer
    add_index :order_items, :dealer_product_id
    add_foreign_key :order_items, :dealer_products, column: :dealer_product_id
  end
end
