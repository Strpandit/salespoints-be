class DropOldDeletionRequestTables < ActiveRecord::Migration[8.0]
  def change
    drop_table :admin_deletion_requests
    drop_table :dealer_deletion_requests
    drop_table :account_deletion_requests
  end
end
