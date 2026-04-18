class UnifyNotificationsAndDeletionRequests < ActiveRecord::Migration[8.0]
  class LegacyDealerNotification < ApplicationRecord
    self.table_name = "dealer_notifications"
  end

  class MigrationNotification < ApplicationRecord
    self.table_name = "notifications"
  end

  def up
    rename_table :app_notifications, :notifications

    rename_column :notifications, :recipient_type, :receiver_type
    rename_column :notifications, :recipient_id, :receiver_id
    rename_column :notifications, :kind, :notification_type
    rename_column :notifications, :message, :body

    add_column :notifications, :sent_at, :datetime

    execute "UPDATE notifications SET sent_at = created_at WHERE sent_at IS NULL"
    execute "UPDATE notifications SET read_at = COALESCE(read_at, updated_at) WHERE status = 'read' AND read_at IS NULL"

    remove_index :notifications, name: "index_app_notifications_on_status" if index_exists?(:notifications, :status, name: "index_app_notifications_on_status")

    remove_column :notifications, :status, :string

    if index_exists?(:notifications, [:receiver_type, :receiver_id], name: "index_app_notifications_on_recipient")
      rename_index :notifications, "index_app_notifications_on_recipient", "index_notifications_on_receiver"
    end
    if index_exists?(:notifications, [:notifiable_type, :notifiable_id], name: "index_app_notifications_on_notifiable")
      rename_index :notifications, "index_app_notifications_on_notifiable", "index_notifications_on_notifiable"
    end

    add_index :notifications, :read_at unless index_exists?(:notifications, :read_at)

    LegacyDealerNotification.reset_column_information
    MigrationNotification.reset_column_information

    LegacyDealerNotification.find_each do |dn|
      payload = (dn.payload || {}).stringify_keys
      payload["b2b_state"] =
        case dn.status
        when "cancelled" then "cancelled"
        when "accepted" then "accepted"
        else "open"
        end

      MigrationNotification.create!(
        receiver_type: "Dealer",
        receiver_id: dn.dealer_id,
        notifiable_type: dn.b2b_order_id.present? ? "B2bOrder" : nil,
        notifiable_id: dn.b2b_order_id,
        notification_type: dn.kind,
        title: dn.title,
        body: dn.message,
        payload: payload,
        read_at: dn.read_at,
        sent_at: dn.created_at,
        created_at: dn.created_at,
        updated_at: dn.updated_at
      )
    end

    drop_table :dealer_notifications

    create_table :dealer_deletion_requests do |t|
      t.references :dealer, null: false, foreign_key: true
      t.references :reviewed_by_admin, foreign_key: { to_table: :admin_users }
      t.string :status, null: false, default: "pending"
      t.text :reason
      t.text :rejection_reason
      t.datetime :requested_at, null: false
      t.datetime :reviewed_at
      t.datetime :password_verified_at

      t.timestamps
    end
    add_index :dealer_deletion_requests, :status
    add_index :dealer_deletion_requests, [:dealer_id, :status]

    create_table :admin_deletion_requests do |t|
      t.references :admin_user, null: false, foreign_key: { to_table: :admin_users }
      t.references :reviewed_by_admin, foreign_key: { to_table: :admin_users }
      t.string :status, null: false, default: "pending"
      t.text :reason
      t.text :rejection_reason
      t.datetime :requested_at, null: false
      t.datetime :reviewed_at
      t.datetime :password_verified_at

      t.timestamps
    end
    add_index :admin_deletion_requests, :status
    add_index :admin_deletion_requests, [:admin_user_id, :status]
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
