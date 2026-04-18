class AddApprovalFieldsToWholesalerPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :wholesaler_posts, :approve_status, :string, default: "pending", null: false
    add_column :wholesaler_posts, :reviewed_at, :datetime
    add_column :wholesaler_posts, :rejection_reason, :text
    add_reference :wholesaler_posts, :reviewed_by_admin, foreign_key: { to_table: :admin_users }

    add_index :wholesaler_posts, :approve_status
  end
end
