class CreateDealerBroadcastTrackers < ActiveRecord::Migration[8.0]
  def change
    create_table :dealer_broadcast_trackers do |t|
      t.integer :broadcast_radius_km, default: 5
      t.integer :attempt_count, default: 1
      t.datetime :last_broadcast_at
      t.string :status, default: "pending"
      t.references :dealer, null: false, foreign_key: true
      t.references :b2b_order, null: false, foreign_key: true

      t.timestamps
    end

    add_column :b2b_orders, :current_broadcast_radius, :integer, default: 5
    add_column :b2b_orders, :broadcast_attempts, :integer, default: 0

    add_index :dealer_broadcast_trackers, [:b2b_order_id, :dealer_id], unique: true, name: "idx_broadcast_trackers_order_dealer"
    add_index :dealer_broadcast_trackers, [:b2b_order_id, :status], name: "idx_broadcast_trackers_order_status"
    add_index :b2b_orders, :current_broadcast_radius
    add_index :b2b_orders, :broadcast_attempts
  end
end
