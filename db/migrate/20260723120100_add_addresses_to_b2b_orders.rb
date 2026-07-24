class AddAddressesToB2bOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :b2b_orders, :billing_address, :jsonb, null: false, default: {}
    add_column :b2b_orders, :shipping_address, :jsonb, null: false, default: {}
    change_column_null :order_offers, :notification_id, true
    add_reference :addresses, :dealer, foreign_key: true, index: true
  end
end
