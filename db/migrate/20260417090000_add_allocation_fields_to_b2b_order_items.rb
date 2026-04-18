class AddAllocationFieldsToB2bOrderItems < ActiveRecord::Migration[8.0]
  def change
    add_column :b2b_order_items, :status, :string, null: false, default: "open"
    add_column :b2b_order_items, :responded_at, :datetime

    add_index :b2b_order_items, :status
  end
end
