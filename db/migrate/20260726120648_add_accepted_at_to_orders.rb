class AddAcceptedAtToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :accepted_at, :datetime
  end
end
