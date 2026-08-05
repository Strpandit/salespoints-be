module Api
  class RolesController < ApplicationController
    before_action :require_admin
    before_action :authorize_roles_read, only: [:index, :active_roles, :show, :modules]
    before_action :authorize_roles_write, only: [:create, :update, :deactivate, :reactivate, :destroy]
    before_action :find_role, only: [:show, :update, :deactivate, :reactivate, :destroy]

    def index
      roles = Role.all.order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      render json: serialize_resource(roles, RoleSerializer).merge(
        meta: {
          current_page: roles.current_page,
          next_page: roles.next_page,
          prev_page: roles.prev_page,
          total_pages: roles.total_pages,
          total_count: roles.total_count
        },
        message: "Roles fetched successfully"
      ), status: :ok
    end

    def active_roles
      roles = Role.where(is_active: true).order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      render json: serialize_resource(roles, RoleSerializer).merge(
        meta: {
          current_page: roles.current_page,
          next_page: roles.next_page,
          prev_page: roles.prev_page,
          total_pages: roles.total_pages,
          total_count: roles.total_count
        },
        message: "Active roles fetched successfully"
      ), status: :ok
    end

    def create
      role = Role.new(role_params.merge(created_by: current_admin))

      if role.save
        notify_admins_entity_created(role)
        render json: serialize_resource(role, RoleSerializer).merge(
          message: "Role created successfully"
        ), status: :created
      else
        render json: { error: role.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def show
      render json: serialize_resource(@role, RoleSerializer).merge(
        message: "Role fetched successfully"
      ), status: :ok
    end

    def update
      if @role.update(role_params)
        notify_admins_entity_updated(@role)
        render json: serialize_resource(@role, RoleSerializer).merge(message: "Role updated successfully"), status: :ok
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
      notify_admins_entity_deleted(@role)
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
      raw_role_params = params.require(:role)
      {
        name: raw_role_params[:name],
        is_active: raw_role_params[:is_active],
        module_permissions: normalize_module_permissions(raw_role_params[:module_permissions]),
      }.tap do |attrs|
        attrs[:module_access] = attrs[:module_permissions].keys
      end
    end

    def normalize_module_permissions(raw_permissions)
      permissions_hash =
        case raw_permissions
        when ActionController::Parameters
          raw_permissions.to_unsafe_h
        when Hash
          raw_permissions
        else
          {}
        end

      permissions_hash.each_with_object({}) do |(module_name, permissions), acc|
        next unless Role::ALLOWED_MODULES.include?(module_name.to_s)

        normalized = Array(permissions).map(&:to_s).select { |perm| Role::ALLOWED_PERMISSIONS.include?(perm) }.uniq
        acc[module_name.to_s] = normalized if normalized.any?
      end
    end

    def find_role
      @role = Role.find_by(id: params[:id])
      return if @role

      render json: { error: "Role not found" }, status: :not_found and return
    end

    def require_admin
      render json: { error: "Admin only" }, status: :unauthorized unless current_user_type == "AdminUser"
    end

    def current_admin
      current_user
    end

    def authorize_roles_read
      return if current_admin.super_admin? || current_admin.can_access?(:roles, :read)

      render json: { error: "You do not have permission to view roles" }, status: :forbidden
    end

    def authorize_roles_write
      return if current_admin.super_admin? || current_admin.can_access?(:roles, :write)

      render json: { error: "You do not have permission to manage roles" }, status: :forbidden
    end

    ### notification helpers
    def get_admin_emails
      AdminUser.where(is_super_admin: true).pluck(:email)
    end

    def notify_admins_entity_created(role)
      details = role.attributes.except("id", "created_at", "updated_at")
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_created(email, "Role", role.name, current_admin, details).deliver_later
      end
    end

    def notify_admins_entity_updated(role)
      changes = role.saved_changes.except("updated_at", "created_at").transform_values { |v| { from: v[0], to: v[1] } }
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_updated(email, "Role", role.name, current_admin, changes).deliver_later
      end
    end

    def notify_admins_entity_deleted(role)
      details = role.attributes.except("id", "created_at", "updated_at")
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_deleted(email, "Role", role.name, current_admin, details).deliver_later
      end
    end
  end
end
