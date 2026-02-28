class AdminRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_roles do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true

      t.timestamps
    end

    add_index :admin_roles, [:admin_user_id, :role_id], unique: true
  end
end
