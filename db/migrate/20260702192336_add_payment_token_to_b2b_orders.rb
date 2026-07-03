class AddPaymentTokenToB2bOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :b2b_orders, :payment_token, :string
    add_index :b2b_orders, :payment_token, unique: true
  end
end
