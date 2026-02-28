class AdminUserSerializer < ActiveModel::Serializer
  attributes :id, :first_name, :last_name, :email, :phone, :status, :country_code, :role

  def role
    object.roles&.map do |role|
      { id: role.id, name: role.name, module_access: role.module_access }
    end
  end
end
