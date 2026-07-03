class AddReferenceNumberInOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :b2b_orders, :reference_number, :string, default: ""
    add_index :b2b_orders, :reference_number, unique: true
  end
end
