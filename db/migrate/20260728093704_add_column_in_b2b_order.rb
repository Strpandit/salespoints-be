class AddColumnInB2bOrder < ActiveRecord::Migration[8.0]
  def change
    add_column :order_offers, :shipped_token, :string
    add_column :b2b_order_offers, :shipped_token, :string
    add_index :order_offers, :shipped_token, unique: true
    add_index :b2b_order_offers, :shipped_token, unique: true

    add_column :b2b_orders, :payment_gateway, :string
    add_column :b2b_orders, :payment_session_id, :string
    add_column :b2b_orders, :payment_reference, :string
    add_column :b2b_orders, :gateway_order_reference, :string
    add_column :b2b_orders, :payment_gateway_payload, :jsonb, default: {}

    add_index :b2b_orders, :gateway_order_reference, name: "idx_b2b_orders_on_gateway_order_reference"
    add_index :b2b_orders, :payment_reference, name: "idx_b2b_orders_on_payment_reference"
  end
end
