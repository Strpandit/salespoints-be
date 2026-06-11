class CreateDeletionRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :deletion_requests do |t|
      t.references :requestable, polymorphic: true, null: false, index: true
      t.references :reviewed_by_admin, foreign_key: { to_table: :admin_users }
      t.string :status, null: false, default: "pending"
      t.text :reason
      t.text :rejection_reason
      t.datetime :requested_at, null: false
      t.datetime :reviewed_at
      t.datetime :password_verified_at
      t.timestamps
    end

    add_index :deletion_requests, :status
  end
end
