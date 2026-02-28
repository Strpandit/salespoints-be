module Api
  class AdminRolesController < ApplicationController
    before_action :require_admin
    before_action :require_super_admin

    def assign_role
      admin = AdminUser.find_by(id: params[:admin_user_id])
      return render json: { error: "Admin user not found"}, status: :not_found unless admin

      roles = Role.where(id: params[:role_ids])
      return render json: { error: "Invalid role ids"}, status: :not_found if roles.empty?

      AdminRole.where(admin_user: admin).delete_all

      roles.each do |role|
        AdminRole.create!(admin_user: admin, role: role)
      end

      render json: {
        message: "Roles assigned successfully",
        admin_id: admin.id,
        roles: roles.pluck(:name)
        # roles: roles.map { |r| { id: r.id, name: r.name } }
      }, status: :ok
    end

    private

    def require_admin
      render json: { error: "Admin only" }, status: :unauthorized unless current_user_type == "AdminUser"
    end

    def require_super_admin
      render json: { error: "Only super admin allowed"}, status: :forbidden unless current_admin.super_admin?
    end

    def current_admin
      current_user
    end
  end
end
