class RoleSerializer < ActiveModel::Serializer
  attributes :id, :name, :is_active, :module_access, :module_permissions

  belongs_to :created_by, serializer: AdminUserSerializer

  def module_permissions
    object.module_permissions || {}
  end
end
