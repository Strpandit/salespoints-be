class CreateOrderBroadcastTrackers < ActiveRecord::Migration[8.0]
  def change
    create_table :order_broadcast_trackers do |t|
      t.references :order, null: false, foreign_key: true
      t.references :dealer, null: false, foreign_key: true
      t.integer :broadcast_radius_km, default: 5
      t.integer :attempt_count, default: 1
      t.string :status, default: "pending"
      t.datetime :last_broadcast_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :order_broadcast_trackers, [:order_id, :dealer_id], unique: true, name: "idx_order_broadcast_trackers_order_dealer"
    add_index :order_broadcast_trackers, [:order_id, :status], name: "idx_order_broadcast_trackers_order_status"
  end
end
