class AdminUserSerializer < ActiveModel::Serializer
  attributes :id, :first_name, :last_name, :email, :phone, :status, :country_code, :role, :is_super_admin

  def role
    object.roles&.map do |role|
      { id: role.id, name: role.name, module_access: role.module_access, module_permissions: role.module_permissions }
    end
  end
end
