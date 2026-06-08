class AddSalaryToAdminUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :admin_users, :salary, :decimal, precision: 15, scale: 2
  end
end
