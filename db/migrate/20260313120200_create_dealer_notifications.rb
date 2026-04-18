class CreateDealerNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :dealer_notifications do |t|
      t.references :dealer, null: false, foreign_key: true
      t.references :b2b_order, foreign_key: true
      t.string :kind, null: false, default: "b2b_order_request"
      t.string :title, null: false
      t.text :message
      t.jsonb :payload, default: {}
      t.string :status, null: false, default: "unread"
      t.datetime :read_at

      t.timestamps
    end

    add_index :dealer_notifications, :status
  end
end
