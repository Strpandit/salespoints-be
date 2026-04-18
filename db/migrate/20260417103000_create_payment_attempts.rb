class CreatePaymentAttempts < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_attempts do |t|
      t.string :attempt_number, null: false
      t.string :buyer_type, null: false
      t.bigint :buyer_id, null: false
      t.string :status, null: false, default: "pending"
      t.decimal :amount, precision: 12, scale: 2, null: false, default: "0.0"
      t.string :currency, null: false, default: "INR"
      t.string :coupon_code
      t.jsonb :billing_address, null: false, default: {}
      t.jsonb :shipping_address, null: false, default: {}
      t.jsonb :cart_snapshot, null: false, default: {}
      t.string :payment_gateway, null: false, default: "cashfree"
      t.string :gateway_order_reference
      t.string :payment_session_id
      t.string :payment_reference
      t.jsonb :payment_gateway_payload, null: false, default: {}
      t.text :failure_reason
      t.datetime :paid_at
      t.datetime :cancelled_at
      t.datetime :failed_at
      t.datetime :processed_at
      t.jsonb :result_payload, null: false, default: {}
      t.timestamps
    end

    add_index :payment_attempts, :attempt_number, unique: true
    add_index :payment_attempts, [:buyer_type, :buyer_id]
    add_index :payment_attempts, :gateway_order_reference
    add_index :payment_attempts, :payment_reference
    add_index :payment_attempts, :status
  end
end
