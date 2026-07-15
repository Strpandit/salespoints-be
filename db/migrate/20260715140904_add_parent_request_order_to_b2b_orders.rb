class AddParentRequestOrderToB2bOrders < ActiveRecord::Migration[8.0]
  def change
    add_reference :b2b_orders, :parent_request_order, null: true, index: true, foreign_key: { to_table: :b2b_orders }
    add_index :b2b_orders, :parent_request_order_id,  unique: true, where: "parent_request_order_id IS NOT NULL", name: "idx_unique_parent_request_order"

    reversible do |dir|
      dir.up do
        remove_column :products, :stock_quantity
      end

      dir.down do
        add_column :products, :stock_quantity, :integer, default: 1
      end
    end
  end
end
