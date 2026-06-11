class AddDeletionAudit < ActiveRecord::Migration[8.0]
  def change
    add_reference :admin_users, :deleted_by, foreign_key: { to_table: :admin_users }
    add_reference :dealers, :deleted_by, foreign_key: { to_table: :admin_users }
  end
end
