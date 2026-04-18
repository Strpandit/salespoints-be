class RoleSerializer < ApplicationSerializer
  attributes :name, :is_active, :module_access

  belongs_to :created_by, serializer: AdminUserSerializer

  def module_permissions
    object.module_permissions || {}
  end
end
