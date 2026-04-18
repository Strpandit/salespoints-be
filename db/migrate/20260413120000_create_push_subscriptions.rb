class CreatePushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :push_subscriptions do |t|
      t.string :subscriber_type, null: false
      t.bigint :subscriber_id, null: false
      t.string :token, null: false
      t.string :platform

      t.timestamps
    end

    add_index :push_subscriptions, [:subscriber_type, :subscriber_id], name: "index_push_subscriptions_on_subscriber"
    add_index :push_subscriptions, :token, unique: true
  end
end
