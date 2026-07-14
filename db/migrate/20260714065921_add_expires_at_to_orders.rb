class AddExpiresAtToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :expires_at, :datetime
    add_index :orders, :expires_at
  end
end
