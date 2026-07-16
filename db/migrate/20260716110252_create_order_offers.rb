class CreateOrderOffers < ActiveRecord::Migration[8.0]
  def change
    create_table :order_offers do |t|
      t.references :order, null: false, foreign_key: true
      t.references :dealer, null: false, foreign_key: true
      t.references :notification, null: false, foreign_key: true
      t.string :status, null: false, default: "open"
      t.string :whatsapp_status, null: false, default: "pending"
      t.string :accept_token, null: false
      t.string :reject_token, null: false
      t.jsonb :item_ids, null: false, default: {}
      t.string :delivery_channel, null: false, default: "whatsapp"
      t.jsonb :delivery_payload, null: false, default: {}
      t.string :recipient_phone
      t.string :whatsapp_message_id
      t.string :whatsapp_status_reason
      t.datetime :whatsapp_status_updated_at
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

    add_index :order_offers, :accept_token, unique: true
    add_index :order_offers, :reject_token, unique: true
    add_index :order_offers, :status
    add_index :order_offers, :whatsapp_status
    add_index :order_offers, [:order_id, :dealer_id]

    if table_exists?(:whatsapp_webhook_events)
      add_reference :whatsapp_webhook_events, :order_offer, foreign_key: true, index: true
    end
  end
end
