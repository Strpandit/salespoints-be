class CreateRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :roles do |t|
      t.string :name
      t.string :module_access, default: '[]'
      t.string :module_permissions, default: '[]'
      t.boolean :is_active, default: true
      t.references :created_by, foreign_key: { to_table: :admin_users }

      t.timestamps
    end
  end
end
