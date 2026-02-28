class AddIsApprovedToDealerProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :dealer_products, :approve_status, :integer, default: 0
    add_index :dealer_products, :approve_status
  end
end
