class AddApprovalFieldsToAdminUsers < ActiveRecord::Migration[8.0]
  def change
    change_table :admin_users, bulk: true do |t|
      t.string :approval_status, null: false, default: "pending"
      t.datetime :approved_at
      t.references :approved_by, foreign_key: { to_table: :admin_users }
    end

    add_index :admin_users, :approval_status
  end
end
