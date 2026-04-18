module Api
  class AdminUsersController < ApplicationController
    before_action :require_admin, except: [:login, :forgot_password, :otp_confirmation, :reset_user_password]
    before_action :require_super_admin, only: [:create, :destroy, :deactivate, :reactivate]
    before_action :find_admin_user, only: [:show, :update, :destroy, :deactivate, :reactivate, :request_deletion, :cancel_deletion_request]
    before_action :authorize_self_deletion_request!, only: [:request_deletion, :cancel_deletion_request]
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
        AdminUser.all.order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      else
        AdminUser.where(is_super_admin: false)
      end

      render json: serialize_resource(admins, AdminUserSerializer).merge(
        meta: {
          current_page: admins.current_page,
          next_page: admins.next_page,
          prev_page: admins.prev_page,
          total_pages: admins.total_pages,
          total_count: admins.total_count
        },
        message: "Admin Users fetched successfully" ), status: :ok
    end

    def create
      admin = AdminUser.new(admin_user_params)
      role_ids = normalized_role_ids

      ActiveRecord::Base.transaction do
        admin.save!
        assign_roles!(admin, role_ids) if role_ids.present?
      end

      deliver_admin_created_email(admin)

      render json: serialize_resource(admin.reload, AdminUserSerializer).merge(
        message: "Admin user created successfully"
      ), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def show
      unless can_view_profile?
        return forbidden("You can view only your own profile")
      end

      render json: serialize_resource(@admin_user, AdminUserSerializer).merge(message: "Profile fetched successfully"), status: :ok
    end

    def update
      unless can_edit_profile?
        return forbidden("You can update only your own profile")
      end

      role_ids = normalized_role_ids

      ActiveRecord::Base.transaction do
        @admin_user.update!(admin_user_params)
        assign_roles!(@admin_user, role_ids) if params.key?(:role_ids)
      end

      render json: serialize_resource(@admin_user.reload, AdminUserSerializer).merge(
        message: "Profile updated successfully"
      )
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def destroy
      forbidden("Admin removal requires an approved deletion request from the staff member profile.")
    end

    def request_deletion
      unless params[:password].present?
        return render json: { message: "Password is required" }, status: :unprocessable_entity
      end

      unless @admin_user.authenticate(params[:password])
        return render json: { message: "Incorrect password" }, status: :unauthorized
      end

      if @admin_user.admin_deletion_requests.pending.exists?
        return render json: { message: "A deletion request is already pending review" }, status: :unprocessable_entity
      end

      req = @admin_user.admin_deletion_requests.create!(
        status: "pending",
        reason: params[:reason].to_s.presence,
        requested_at: Time.current,
        password_verified_at: Time.current
      )

      AdminUser.where(is_super_admin: true).find_each do |admin|
        next if admin.id == @admin_user.id

        NotificationService.deliver(
          recipient: admin,
          actor: @admin_user,
          notifiable: req,
          kind: "admin_deletion_requested",
          title: "Admin staff deletion requested",
          message: "#{@admin_user.full_name.presence || 'Admin'} (#{@admin_user.email}) requested profile removal.",
          payload: { admin_deletion_request_id: req.id, admin_user_id: @admin_user.id }
        )
      end

      render json: {
        message: "Deletion request submitted. A super administrator will review it.",
        data: { pending_deletion_request: true }
      }, status: :ok
    end

    def cancel_deletion_request
      req = @admin_user.admin_deletion_requests.pending.order(created_at: :desc).first
      return render json: { message: "No pending deletion request" }, status: :not_found unless req

      req.destroy!
      render json: { message: "Deletion request cancelled", data: { pending_deletion_request: false } }, status: :ok
    end

    def forgot_password
      admin = AdminUser.find_by(email: params[:email]&.downcase)
      return unauthorized("User not found") unless admin
      return render json: { error: "Admin email not available" }, status: :unprocessable_entity if admin.email.blank?

      admin.update!(
        otp_pin: rand(1000..9999),
        otp_sent_at: Time.current
      )

      AdminAuthMailer.forgot_password_otp(admin).deliver_later if admin.email.present?

      render json: { message: "OTP sent successfully", id: admin.id }
    end

    def otp_confirmation
      admin = AdminUser.find(params[:id])
      return unauthorized("Invalid OTP") unless admin.otp_pin.to_s == params[:otp].to_s

      render json: { message: "OTP verified successfully" }
    end

    def reset_user_password
      admin = AdminUser.find(params[:id])

      if admin.update(password: params[:password], password_confirmation: params[:password_confirmation])
        admin.update(otp_pin: nil, otp_sent_at: nil)
        AdminAuthMailer.password_reset_confirmation(admin).deliver_later if admin.email.present?
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

    def authorize_self_deletion_request!
      return forbidden("You can only request deletion for your own profile") unless current_admin.id == @admin_user.id
      return forbidden("Super admin cannot use this deletion request flow") if @admin_user.is_super_admin?
    end

    def normalized_role_ids
      Array(params[:role_ids]).map(&:to_i).uniq
    end

    def assign_roles!(admin, role_ids)
      roles = Role.where(id: role_ids)
      return if role_ids.blank?

      if roles.size != role_ids.size
        admin.errors.add(:roles, "contain invalid role ids")
        raise ActiveRecord::RecordInvalid.new(admin)
      end

      admin.roles = roles
    end

    def deliver_admin_created_email(admin)
      password_for_email = admin.generated_password.presence || params.dig(:admin_user, :password)
      return if password_for_email.blank?

      AdminAuthMailer.admin_created(admin, password_for_email).deliver_later
    rescue StandardError => e
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
