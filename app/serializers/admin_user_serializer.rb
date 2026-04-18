class AdminUserSerializer < ApplicationSerializer
  attributes :first_name, :last_name, :email, :phone, :status, :country_code, :is_super_admin, :full_name, :pending_deletion_request, :role

  def pending_deletion_request
    object.admin_deletion_requests.pending.exists?
  end

  def role
    object.roles&.map do |role|
      {
        id: role.id,
        name: role.name,
        is_active: role.is_active,
        module_access: role.module_access,
        module_permissions: role.module_permissions
      }
    end
  end
end
