class CreateAccountDeletionRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :account_deletion_requests do |t|
      t.references :account, null: false, foreign_key: true
      t.references :reviewed_by_admin, foreign_key: { to_table: :admin_users }
      t.string :status, null: false, default: "pending"
      t.text :reason
      t.text :rejection_reason
      t.datetime :requested_at, null: false
      t.datetime :reviewed_at
      t.datetime :password_verified_at

      t.timestamps
    end

    add_index :account_deletion_requests, :status
    add_index :account_deletion_requests, [:account_id, :status]
  end
end
