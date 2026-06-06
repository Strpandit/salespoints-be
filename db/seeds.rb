# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
super_admin = AdminUser.find_or_initialize_by(email: 'salespointecom@gmail.com') do |user|
  user.password = 'Salespoints@2026'
  user.password_confirmation = 'Salespoints@2026'
  user.first_name = 'Sales'
  user.last_name = 'Points'
  user.is_super_admin = true
  user.status = 'active'
end
super_admin.update_columns(
  approval_status: 'approved',
  approved_at: Time.current,
  approved_by_id: super_admin.id
)
# if super_admin.approved_by_id.nil?
#   super_admin.update!(approved_by_id: super_admin.id)
# end
role = Role.find_or_create_by!(name: 'Super Admin') do |role|
  role.module_access = Role::ALLOWED_MODULES
  role.is_active = true
  role.created_by_id = super_admin.id
end
AdminRole.find_or_create_by!(admin_user_id: super_admin.id, role_id: role.id)