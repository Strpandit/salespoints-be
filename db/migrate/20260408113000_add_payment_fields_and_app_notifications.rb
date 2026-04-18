class AddPaymentFieldsAndAppNotifications < ActiveRecord::Migration[8.0]
  def change
    change_table :orders, bulk: true do |t|
      t.string :payment_gateway
      t.string :gateway_order_reference
      t.string :payment_session_id
      t.string :payment_reference
      t.jsonb :payment_gateway_payload, default: {}, null: false
      t.text :status_note
      t.datetime :payment_confirmed_at
      t.datetime :cancelled_at
      t.datetime :delivered_at
      t.datetime :shipped_at
      t.datetime :processing_at
    end

    add_index :orders, :payment_reference
    add_index :orders, :gateway_order_reference

    create_table :app_notifications do |t|
      t.string :recipient_type, null: false
      t.bigint :recipient_id, null: false
      t.string :actor_type
      t.bigint :actor_id
      t.string :notifiable_type
      t.bigint :notifiable_id
      t.string :kind, null: false
      t.string :title, null: false
      t.text :message
      t.jsonb :payload, default: {}, null: false
      t.string :status, null: false, default: "unread"
      t.datetime :read_at

      t.timestamps
    end

    add_index :app_notifications, [:recipient_type, :recipient_id], name: "index_app_notifications_on_recipient"
    add_index :app_notifications, [:notifiable_type, :notifiable_id], name: "index_app_notifications_on_notifiable"
    add_index :app_notifications, :status
  end
end
