module Api
  class AdminUsersController < ApplicationController
    before_action :require_admin, except: [:login, :forgot_password, :otp_confirmation, :reset_user_password]
    before_action :require_super_admin, only: [:create, :destroy, :deactivate, :reactivate]
    before_action :find_admin_user, only: [:show, :update, :destroy, :deactivate, :reactivate]
    skip_before_action :authenticate_request!, only: [:login, :forgot_password, :otp_confirmation, :reset_user_password]

    def login
      admin = AdminUser.find_by(email: params[:email]&.downcase, status: 'active')
      return unauthorized("Invalid credentials") unless admin&.authenticate(params[:password])

      token = JsonWebToken.encode(user_id: admin.id, user_type: "AdminUser")

      # Send login notification email
      AdminAuthMailer.admin_login_notification(admin).deliver_later

      render json: {
        token: token,
        admin: {
          id: admin.id,
          full_name: admin.full_name,
          first_name: admin.first_name,
          last_name: admin.last_name,
          email: admin.email,
          phone: admin.phone,
          is_super_admin: admin.is_super_admin
        },
        message: "Logged in successfully"
      }, status: :ok
    end

    def index
      unless current_admin.can_access?(:admin_users)
        return forbidden("Permission denied")
      end

      admins =
      if current_admin.super_admin?
        AdminUser.all
      else
        AdminUser.where(is_super_admin: false)
      end

      render json: { data: ActiveModelSerializers::SerializableResource.new(admins, each_serializer: AdminUserSerializer), message: "Admin Users fetched successfully" }, status: :ok
    end

    def create
      admin = AdminUser.new(admin_user_params)

      if admin.save
        render json: {
          data: AdminUserSerializer.new(admin),
          message: "Admin user created successfully"
        }, status: :created
      else
        render json: { error: admin.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def show
      unless can_view_profile?
        return forbidden("You can view only your own profile")
      end

      render json: { data: AdminUserSerializer.new(@admin_user), message: "Profile fetched successfully" }, status: :ok
    end

    def update
      unless can_edit_profile?
        return forbidden("You can update only your own profile")
      end

      if @admin_user.update(admin_user_params)
        render json: {
          data: AdminUserSerializer.new(@admin_user),
          message: "Profile updated successfully"
        }
      else
        render json: { error: @admin_user.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      return forbidden("Super admin cannot be deleted") if @admin_user.is_super_admin?

      @admin_user.update!(status: "inactive")
      render json: { message: "Admin user deactivated successfully" }
    end

    def forgot_password
      admin = AdminUser.find_by(email: params[:email]&.downcase)
      return unauthorized("User not found") unless admin

      admin.update!(
        otp_pin: rand(1000..9999),
        otp_sent_at: Time.current
      )

      render json: { message: "OTP sent successfully", id: admin.id }
    end

    def otp_confirmation
      admin = AdminUser.find(params[:id])
      return unauthorized("Invalid OTP") unless admin.otp_pin == params[:otp]

      render json: { message: "OTP verified successfully" }
    end

    def reset_user_password
      admin = AdminUser.find(params[:id])

      if admin.update(password: params[:password], password_confirmation: params[:password_confirmation])
        admin.update(otp_pin: nil, otp_sent_at: nil)
        render json: { message: "Password reset successfully" }
      else
        render json: { error: admin.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def change_password
      unless current_admin.authenticate(params[:current_password])
        return unauthorized("Incorrect current password")
      end

      if current_admin.update(
        password: params[:new_password],
        password_confirmation: params[:confirm_password]
      )
        render json: { message: "Password changed successfully" }
      else
        render json: { error: current_admin.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def deactivate
      @admin_user.update!(status: "inactive")
      render json: { message: "Admin user deactivated successfully" }
    end

    def reactivate
      @admin_user.update!(status: "active")
      render json: { message: "Admin user reactivated successfully" }
    end

    private

    def admin_user_params
      params.require(:admin_user).permit(
        :first_name, :last_name, :email, :phone,
        :password, :password_confirmation, :status
      )
    end

    def find_admin_user
      @admin_user = AdminUser.find_by(id: params[:id])
      unauthorized("Admin user not found") unless @admin_user
    end

    def require_admin
      unauthorized("Admin only") unless current_user_type == "AdminUser"
    end

    def require_super_admin
      forbidden("Only super admin allowed") unless current_admin.super_admin?
    end

    def can_edit_profile?
      current_admin.super_admin? || current_admin.id == @admin_user.id
    end

    def can_view_profile?
      current_admin.super_admin? || current_admin.id == @admin_user.id
    end

    def current_admin
      current_user
    end

    def unauthorized(msg)
      render json: { error: msg }, status: :unauthorized and return
    end

    def forbidden(msg)
      render json: { error: msg }, status: :forbidden and return
    end
  end
end
