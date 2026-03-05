module Api
  class RolesController < ApplicationController
    before_action :require_admin
    before_action :require_super_admin
    before_action :find_role, only: [:show, :update, :deactivate, :reactivate]

    def index
      roles = Role.all
      render json: {
        data: ActiveModelSerializers::SerializableResource.new(roles, each_serializer: RoleSerializer),
        message: "Roles fetched successfully"
      }, status: :ok
    end

    def active_roles
      roles = Role.where(is_active: true)
      render json: {
        data: ActiveModelSerializers::SerializableResource.new(roles, each_serializer: RoleSerializer),
        message: "Active roles fetched successfully"
      }, status: :ok
    end

    def create
      role = Role.new(role_params.merge(created_by: current_admin))

      if role.save
        notify_admins_entity_created(role)
        render json: {
          data: RoleSerializer.new(role),
          message: "Role created successfully"
        }, status: :created
      else
        render json: { error: role.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def show
      render json: {
        data: RoleSerializer.new(@role),
        message: "Role fetched successfully"
      }, status: :ok
    end

    def update
      if @role.update(role_params)
        notify_admins_entity_updated(@role)
        render json: { data: RoleSerializer.new(@role), message: "Role updated successfully" }, status: :ok
      else
        render json: {
          error: @role.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def deactivate
      @role.update(is_active: false)
      render json: { message: "Role deactivated successfully" }, status: :ok
    end

    def reactivate
      @role.update(is_active: true)
      render json: { message: "Role reactivated successfully" }, status: :ok
    end

    def destroy
      @role.destroy
      render json: { message: "Role deleted successfully" }, status: :ok
    end

    def modules
      modules = Role::ALLOWED_MODULES
      render json: {
        modules: modules
      }, status: :ok
    end

    private

    def role_params
      params.require(:role).permit(:name, :is_active, module_access: [], module_permissions: [])
    end

    def find_role
      @role = Role.find_by(id: params[:id])
      render json: { error: "Role not found" }, status: :not_found unless @role
    end

    def require_super_admin
      render json: { error: "Only Super Admin allowed" }, status: :forbidden unless current_admin.super_admin?
    end

    def require_admin
      render json: { error: "Admin only" }, status: :unauthorized unless current_user_type == "AdminUser"
    end

    def current_admin
      current_user
    end

    ### notification helpers
    def get_admin_emails
      AdminUser.where(is_super_admin: true).pluck(:email)
    end

    def notify_admins_entity_created(role)
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_created(email, "Role", role.name, current_admin&.email).deliver_later
      end
    end

    def notify_admins_entity_updated(role)
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_updated(email, "Role", role.name, current_admin&.email).deliver_later
      end
    end
  end
end
