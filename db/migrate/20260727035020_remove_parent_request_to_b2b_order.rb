class RemoveParentRequestToB2bOrder < ActiveRecord::Migration[8.0]
  def change
    if column_exists?(:b2b_orders, :parent_request_order_id)
      if index_exists?(:b2b_orders, :parent_request_order_id, name: "idx_unique_parent_request_order")
        remove_index :b2b_orders, name: "idx_unique_parent_request_order"
      end
      
      if index_exists?(:b2b_orders, :parent_request_order_id, name: "index_b2b_orders_on_parent_request_order_id")
        remove_index :b2b_orders, name: "index_b2b_orders_on_parent_request_order_id"
      end
      
      if foreign_key_exists?(:b2b_orders, column: :parent_request_order_id)
        remove_foreign_key :b2b_orders, column: :parent_request_order_id
      end
      
      remove_column :b2b_orders, :parent_request_order_id, :bigint
    end
  end
end