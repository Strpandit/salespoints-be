class CreateDeliveryConfirmationsAndB2bDeliveryFields < ActiveRecord::Migration[8.0]
  def change
    create_table :delivery_confirmations do |t|
      t.string :token, null: false
      t.string :deliverable_type, null: false
      t.bigint :deliverable_id, null: false
      t.bigint :seller_dealer_id
      t.string :buyer_type, null: false
      t.bigint :buyer_id, null: false
      t.string :status, null: false, default: "pending_form"
      t.jsonb :declarations, null: false, default: {}
      t.text :notes
      t.string :seller_phone
      t.string :buyer_phone
      t.string :seller_otp
      t.datetime :seller_otp_sent_at
      t.datetime :seller_otp_verified_at
      t.string :buyer_otp
      t.datetime :buyer_otp_sent_at
      t.datetime :buyer_otp_verified_at
      t.datetime :submitted_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :delivery_confirmations, :token, unique: true
    add_index :delivery_confirmations, [:deliverable_type, :deliverable_id], unique: true, name: "idx_delivery_confirmations_on_deliverable"
    add_index :delivery_confirmations, [:buyer_type, :buyer_id]
    add_index :delivery_confirmations, :seller_dealer_id
    add_index :delivery_confirmations, :status

    add_column :b2b_orders, :shipped_at, :datetime
    add_column :b2b_orders, :delivered_at, :datetime
    add_column :b2b_orders, :status_note, :text
  end
end
