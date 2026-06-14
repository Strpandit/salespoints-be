module Api
  class AdminUsersController < ApplicationController
    skip_before_action :authenticate_request!, only: [:login, :login_otp, :forgot_password, :otp_confirmation, :reset_user_password, :verify_otp]
    before_action :require_admin, except: [:login, :login_otp, :forgot_password, :otp_confirmation, :reset_user_password, :verify_otp]
    before_action :require_super_admin, only: [:create, :destroy, :deactivate, :reactivate]
    before_action :find_admin_user, only: [:show, :update, :destroy, :deactivate, :reactivate, :approve, :verify_otp, :login_otp]
    before_action :require_admin_approver!, only: [:approve]

    def login
      admin = AdminUser.find_by(email: params[:email]&.downcase, status: 'active')
      return unauthorized("Admin account not found") unless admin
      return forbidden("Your admin onboarding is still pending approval") unless admin.approved?
      return unauthorized("Invalid credentials") unless admin&.authenticate(params[:password])

      if admin.super_admin?
        admin.update!(otp_pin: rand(1000..9999), otp_sent_at: Time.current)
        AdminAuthMailer.login_otp(admin).deliver_later if admin.email.present?

        render json: {
          otp_required: true,
          admin: {
            id: admin.id,
            email: admin.email,
            full_name: admin.full_name
          },
          message: "OTP sent to your email. Please verify to complete login."
        }, status: :ok
      else
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
    end

    def index
      unless current_admin.can_access?(:admin_users)
        return forbidden("Permission denied")
      end

      admins =
      if current_admin.super_admin?
        AdminUser.order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      else
        AdminUser.where(is_super_admin: false)
      end

      render json: serialize_resource(admins, AdminUserSerializer, serializer_options).merge(
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
      admin = AdminUser.new(admin_user_params.except(:status))
      admin.approval_status = "pending"
      admin.status = "inactive"
      admin.otp_pin = rand(1000..9999)
      admin.otp_sent_at = Time.current

      temp_password = SecureRandom.hex(6)
      admin.password = temp_password
      admin.password_confirmation = temp_password

      unless admin.email.present?
        return render json: { error: "Admin email is required for OTP verification" }, status: :unprocessable_entity
      end

      role_ids = normalized_role_ids

      ActiveRecord::Base.transaction do
        admin.save!
        assign_roles!(admin, role_ids) if role_ids.present?
      end

      AdminAuthMailer.signup_otp(admin).deliver_later if admin.email.present?
      notify_admin_approvers(admin)

      verify_url = "#{ENV['FRONTEND_URL'] || request.base_url}/admin/verify-otp?id=#{admin.id}&email=#{CGI.escape(admin.email)}"
      render json: serialize_resource(admin.reload, AdminUserSerializer, serializer_options).merge(
        message: "Admin user created successfully. OTP sent to admin email.",
        verify_url: verify_url
      ), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def show
      unless can_view_profile?
        return forbidden("You can view only your own profile")
      end

      render json: serialize_resource(@admin_user, AdminUserSerializer, serializer_options).merge(message: "Profile fetched successfully"), status: :ok
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

      render json: serialize_resource(@admin_user.reload, AdminUserSerializer, serializer_options).merge(
        message: "Profile updated successfully"
      )
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def approve
      return render json: { error: "Admin user is already approved" }, status: :unprocessable_entity if @admin_user.approved?
      return render json: { error: "Admin must verify signup OTP before approval" }, status: :unprocessable_entity if @admin_user.otp_pin.present?

      @admin_user.update!(
        approval_status: "approved",
        approved_at: Time.current,
        approved_by: current_admin,
        status: "active"
      )

      AdminAuthMailer.onboarding_approved(@admin_user).deliver_later if @admin_user.email.present?

      render json: serialize_resource(@admin_user.reload, AdminUserSerializer, serializer_options).merge(
        message: "Admin user approved successfully"
      ), status: :ok
    end
      
    def destroy

      return forbidden(
        "You cannot delete your own account"
      ) if @admin_user.id == current_admin.id

      unless current_admin.super_admin?
        return forbidden(
          "Only super admin can directly delete users"
        )
      end

      return forbidden(
        "Super admin accounts cannot be deleted"
      ) if @admin_user.super_admin?

      ActiveRecord::Base.transaction do
        @admin_user.update!(
          deleted_by: current_admin
        )
        @admin_user.destroy
      end

      DeletionNotificationService.direct_deleted(@admin_user, current_admin)
      DeletionMailService.direct_deleted(@admin_user, current_admin)

      render json: {
        message: "Admin deleted successfully"
      }, status: :ok
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

    def login_otp
      return unauthorized("Invalid admin login") unless @admin_user&.super_admin?
      return unauthorized("Invalid OTP") unless @admin_user.otp_valid?(params[:otp].to_s)

      token = JsonWebToken.encode(user_id: @admin_user.id, user_type: "AdminUser")
      @admin_user.clear_otp!
      AdminAuthMailer.admin_login_notification(@admin_user).deliver_later if @admin_user.email.present?

      render json: {
        token: token,
        admin: {
          id: @admin_user.id,
          full_name: @admin_user.full_name,
          first_name: @admin_user.first_name,
          last_name: @admin_user.last_name,
          email: @admin_user.email,
          phone: @admin_user.phone,
          is_super_admin: @admin_user.is_super_admin
        },
        message: "Login successful"
      }, status: :ok
    end

    def otp_confirmation
      admin = AdminUser.find(params[:id])
      return unauthorized("Invalid OTP") unless admin.otp_pin.to_s == params[:otp].to_s

      render json: { message: "OTP verified successfully" }
    end

    def verify_otp
      return unauthorized("Invalid OTP") unless @admin_user.otp_valid?(params[:otp].to_s)

      temp_password = SecureRandom.hex(6)
      @admin_user.update!(password: temp_password, password_confirmation: temp_password, otp_pin: nil, otp_sent_at: nil)
      AdminAuthMailer.admin_created(@admin_user, temp_password).deliver_later if @admin_user.email.present?

      render json: { message: "Admin OTP verified successfully. Credentials have been emailed." }, status: :ok
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
        :first_name, :last_name, :email, :phone, :alternate_phone, :address,
        :aadhar_number, :pan_number, :bank_name, :bank_account_number,
        :ifsc_code, :account_holder_name, :tenth_school_name, :tenth_board,
        :tenth_passing_year, :tenth_percentage, :twelfth_school_name,
        :twelfth_board, :twelfth_passing_year, :twelfth_percentage, :joining_date,
        :password, :password_confirmation, :status, :salary, :staff_profile_pic,
        :aadhar_card, :pan_card, { marksheets: [] }
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

    def notify_admin_approvers(admin)
      approver_scope = AdminUser.active.select { |user| user.approver_admin? && user.email.present? && user.id != admin.id }
      approver_scope.each do |approver|
        AdminAuthMailer.onboarding_approval_request(admin, approver.email).deliver_later
      end
    rescue StandardError
    end

    def current_admin
      current_user
    end

    def require_admin_approver!
      return if current_admin&.approver_admin?

      forbidden("Only Super Admin or Sub Admin can approve admin onboarding")
    end

    def serializer_options
      { base_url: request.base_url }
    end

    def unauthorized(msg)
      render json: { error: msg }, status: :unauthorized and return
    end

    def forbidden(msg)
      render json: { error: msg }, status: :forbidden and return
    end
  end
end
