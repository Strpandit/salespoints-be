class RoleSerializer < ActiveModel::Serializer
  attributes :id, :name, :is_active, :module_access

  belongs_to :created_by, serializer: AdminUserSerializer
end
