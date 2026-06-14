class AddJoiningDateInAdminUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :admin_users, :joining_date, :date
  end
end
