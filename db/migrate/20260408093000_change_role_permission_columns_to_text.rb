class ChangeRolePermissionColumnsToText < ActiveRecord::Migration[8.0]
  def up
    change_column :roles, :module_access, :text
    change_column_default :roles, :module_access, from: "[]", to: "--- []\n"

    unless column_exists?(:roles, :module_permissions)
      add_column :roles, :module_permissions, :text, default: "--- {}\n"
    else
      change_column :roles, :module_permissions, :text
      change_column_default :roles, :module_permissions, from: "[]", to: "--- {}\n"
    end
  end

  def down
    change_column_default :roles, :module_access, from: "--- []\n", to: "[]"
    change_column :roles, :module_access, :string

    if column_exists?(:roles, :module_permissions)
      change_column_default :roles, :module_permissions, from: "--- {}\n", to: "[]"
      change_column :roles, :module_permissions, :string
    end
  end
end