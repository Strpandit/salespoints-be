class AddB2bOfferTrackingAndPaymentFields < ActiveRecord::Migration[8.0]
  def change
    change_table :b2b_orders, bulk: true do |t|
      t.string :payment_method, null: false, default: "cod"
      t.string :payment_status, null: false, default: "pending"
      t.references :buyer_payment_attempt, foreign_key: { to_table: :payment_attempts }
      t.datetime :last_rebroadcast_at
    end

    add_index :b2b_orders, :payment_method
    add_index :b2b_orders, :payment_status

    create_table :b2b_order_offers do |t|
      t.references :b2b_order, null: false, foreign_key: true
      t.references :dealer, null: false, foreign_key: true
      t.references :notification, foreign_key: true
      t.string :status, null: false, default: "open"
      t.string :delivery_channel, null: false, default: "whatsapp"
      t.jsonb :item_ids, null: false, default: []
      t.jsonb :delivery_payload, null: false, default: {}
      t.string :accept_token, null: false
      t.string :reject_token, null: false
      t.string :recipient_phone
      t.string :whatsapp_message_id
      t.string :whatsapp_status, null: false, default: "pending"
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at
      t.datetime :failed_at
      t.datetime :responded_at
      t.datetime :expires_at
      t.integer :rebroadcast_count, null: false, default: 0
      t.text :failure_reason
      t.timestamps
    end

    add_index :b2b_order_offers, :accept_token, unique: true
    add_index :b2b_order_offers, :reject_token, unique: true
    add_index :b2b_order_offers, :status
    add_index :b2b_order_offers, :whatsapp_status
    add_index :b2b_order_offers, [:b2b_order_id, :dealer_id]

    create_table :whatsapp_webhook_events do |t|
      t.string :provider, null: false, default: "meta"
      t.string :event_type, null: false
      t.string :event_key, null: false
      t.string :direction, null: false, default: "inbound"
      t.references :b2b_order_offer, foreign_key: true
      t.references :notification, foreign_key: true
      t.string :message_id
      t.string :conversation_id
      t.string :from_number
      t.string :to_number
      t.string :status
      t.datetime :processed_at
      t.jsonb :payload, null: false, default: {}
      t.text :error_message
      t.timestamps
    end

    add_index :whatsapp_webhook_events, :event_key, unique: true
    add_index :whatsapp_webhook_events, :message_id
    add_index :whatsapp_webhook_events, :event_type
    add_index :whatsapp_webhook_events, :status
  end
end
