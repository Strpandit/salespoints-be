class CreatePaymentGatewayWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_gateway_webhook_events do |t|
      t.string :provider, null: false
      t.string :event_type
      t.string :event_id, null: false
      t.string :payload_digest, null: false
      t.string :status, null: false, default: "received"
      t.integer :response_code
      t.datetime :received_at, null: false
      t.datetime :processed_at
      t.jsonb :headers, null: false, default: {}
      t.jsonb :payload, null: false, default: {}
      t.text :error_message
      t.timestamps
    end

    add_index :payment_gateway_webhook_events, [:provider, :event_id], unique: true, name: "idx_pg_webhook_events_unique"
    add_index :payment_gateway_webhook_events, :status
    add_index :payment_gateway_webhook_events, :received_at
  end
end
