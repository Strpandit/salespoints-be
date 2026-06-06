module Api
  class DealersController < ApplicationController
    skip_before_action :authenticate_request!, only: [:verify_otp]
    before_action :authenticate_request!
    before_action :require_admin, only: [:create, :index, :active_dealers, :block, :unblock, :destroy, :approve, :reject]
    before_action :require_admin_approver!, only: [:approve, :reject]
    before_action :set_dealer, only: [:show, :update, :block, :unblock, :approve, :reject, :verify_otp, :request_deletion, :cancel_deletion_request]
    before_action :authorize_dealer_update, only: [:update, :show]
    before_action :authorize_dealer_self!, only: [:request_deletion, :cancel_deletion_request]

    def index
      dealers = Dealer.where(status: "pending").includes(:dealer_profile, :dealer_location).order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      render json: serialize_resource(dealers, DealerSerializer, base_url: request.base_url).merge(
        meta: {
          current_page: dealers.current_page,
          next_page: dealers.next_page,
          prev_page: dealers.prev_page,
          total_pages: dealers.total_pages,
          total_count: dealers.total_count
        },
        message: "Dealers fetched successfully"
      ), status: :ok
    end

    def active_dealers
      dealers = Dealer.includes(:dealer_profile, :dealer_location)
      selected_status = params[:status].presence || "active"

      if selected_status != "all"
        unless Dealer.statuses.key?(selected_status)
          return render json: { error: "Invalid dealer status" }, status: :unprocessable_entity
        end

        dealers = dealers.where(status: selected_status)
      end

      dealers = dealers.order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      render json: serialize_resource(dealers, DealerSerializer, base_url: request.base_url).merge(
        meta: {
          current_page: dealers.current_page,
          next_page: dealers.next_page,
          prev_page: dealers.prev_page,
          total_pages: dealers.total_pages,
          total_count: dealers.total_count,
          statuses: ["all"] + Dealer.statuses.keys
        },
        message: "Dealers fetched successfully"
      ), status: :ok
    end

    def create
      dealer = Dealer.new(dealer_params.except(:status))
      dealer.status = "pending"
      dealer.otp_pin = rand(1000..9999)
      dealer.otp_sent_at = Time.current

      unless dealer.email.present?
        return render json: { error: "Dealer email is required for OTP verification" }, status: :unprocessable_entity
      end

      if dealer.save
        DealerAuthMailer.signup_otp(dealer).deliver_later if dealer.email.present?
        notify_admins_about_dealer_creation(dealer)

        verify_url = "#{ENV['FRONTEND_URL'] || request.base_url}/dealer/verify-otp?id=#{dealer.id}&email=#{CGI.escape(dealer.email)}"
        render json: serialize_resource(dealer, DealerSerializer, base_url: request.base_url).merge(
          message: "Dealer created successfully. OTP sent to dealer email.",
          verify_url: verify_url
        ), status: :created
      else
        render json: { error: dealer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def show
      render json: serialize_resource(@dealer, DealerSerializer, base_url: request.base_url).merge(
        message: "Dealer fetched successfully"
      ), status: :ok
    end

    def update
      if @dealer.update(dealer_params)
        render json: serialize_resource(@dealer, DealerSerializer, base_url: request.base_url).merge(message: "Dealer updated successfully"), status: :ok
      else
        render json: {
          error: @dealer.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def block
      @dealer.update(status: "banned")
      render json: { message: "Dealer blocked successfully" }, status: :ok
    end

    def unblock
      @dealer.update(status: "active")
      render json: { message: "Dealer unblocked successfully" }, status: :ok
    end

    def approve
      unless @dealer.status == "pending"
        return render json: { error: "Dealer is already processed" }, status: :unprocessable_entity
      end

      if @dealer.otp_pin.present?
        return render json: { error: "Dealer must verify signup OTP before approval" }, status: :unprocessable_entity
      end

      if @dealer.update(status: "active")
        DealerMailer.approval_email(@dealer).deliver_later
        notify_admins_about_dealer_action(@dealer, "approved")

        render json: serialize_resource(@dealer, DealerSerializer, base_url: request.base_url).merge(
          message: "Dealer approved successfully. Approval email sent."
        ), status: :ok
      else
        render json: { error: @dealer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def reject
      unless @dealer.status == "pending"
        return render json: { error: "Dealer is already processed" }, status: :unprocessable_entity
      end

      rejection_reason = params[:reason] || "Application does not meet requirements"

      if @dealer.update(status: "rejected")
        DealerMailer.rejection_email(@dealer, rejection_reason).deliver_later
        notify_admins_about_dealer_action(@dealer, "rejected", rejection_reason)

        render json: serialize_resource(@dealer, DealerSerializer, base_url: request.base_url).merge(
          message: "Dealer rejected successfully. Rejection email sent."
        ), status: :ok
      else
        render json: { error: @dealer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def verify_otp
      unless @dealer.otp_valid?(params[:otp].to_s)
        return render json: { error: "Invalid or expired OTP" }, status: :unauthorized
      end

      temp_password = SecureRandom.hex(6)
      @dealer.update!(password: temp_password, password_confirmation: temp_password, otp_pin: nil, otp_sent_at: nil)
      DealerMailer.welcome_email(@dealer, temp_password).deliver_later if @dealer.email.present?

      render json: { message: "Dealer OTP verified successfully. Credentials have been emailed." }, status: :ok
    end

    def destroy
      render json: {
        error: "Direct deletion is disabled. Dealers must submit a deletion request; an administrator will approve it."
      }, status: :forbidden
    end

    def request_deletion
      unless params[:password].present?
        return render json: { message: "Password is required" }, status: :unprocessable_entity
      end

      unless @dealer.authenticate(params[:password])
        return render json: { message: "Incorrect password" }, status: :unauthorized
      end

      if @dealer.dealer_deletion_requests.pending.exists?
        return render json: { message: "A deletion request is already pending review" }, status: :unprocessable_entity
      end

      req = @dealer.dealer_deletion_requests.create!(
        status: "pending",
        reason: params[:reason].to_s.presence,
        requested_at: Time.current,
        password_verified_at: Time.current
      )

      AdminUser.find_each do |admin|
        next unless admin.can_access?(:dealers, :write)

        NotificationService.deliver(
          recipient: admin,
          actor: @dealer,
          notifiable: req,
          kind: "dealer_deletion_requested",
          title: "Dealer deletion requested",
          message: "#{@dealer.full_name.presence || 'Dealer'} (#{@dealer.email}) requested account deletion.",
          payload: { dealer_deletion_request_id: req.id, dealer_id: @dealer.id }
        )
      end

      render json: {
        message: "Deletion request submitted. An administrator will review it.",
        data: { pending_deletion_request: true }
      }, status: :ok
    end

    def cancel_deletion_request
      req = @dealer.dealer_deletion_requests.pending.order(created_at: :desc).first
      return render json: { message: "No pending deletion request" }, status: :not_found unless req

      req.destroy!
      render json: { message: "Deletion request cancelled", data: { pending_deletion_request: false } }, status: :ok
    end

    private

    def authorize_dealer_self!
      return if current_user_type == "Dealer" && current_dealer.present? && current_dealer.id == @dealer.id

      render json: { error: "Unauthorized" }, status: :forbidden
    end

    def dealer_params
      params.require(:dealer).permit(
        :first_name, :last_name, :email, :phone, :gender, :country_code, :status, :password, :password_confirmation,
        dealer_profile_attributes: [
          :business_name, :business_type, :gst_number, :pan_number, :aadhar_number,
          :bank_name, :bank_account_number, :ifsc_code, :business_address,
          :business_contact_number, :business_email, :work_category, :associated_brands,
          :is_verified, { store_image: [] }
        ],
        dealer_location_attributes: [:latitude, :longitude, :service_radius_km, :is_active]
      )
    end

    def set_dealer
      @dealer = Dealer.find_by(id: params[:id])
      render json: { error: "Dealer not found" }, status: :not_found unless @dealer
    end

    def require_admin
      render json: { error: "Admin only" }, status: :unauthorized unless current_user_type == "AdminUser"
    end

    def authorize_dealer_update
      # allow admin or the dealer themselves to view/update profile
      return if current_user_type == "AdminUser"
      if current_user_type == "Dealer" && current_user.id == @dealer.id
        return
      end
      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def get_admin_emails
      AdminUser.active.select { |admin| admin.approver_admin? && admin.email.present? }.map(&:email)
    end

    def notify_admins_about_dealer_creation(dealer)
      admin_emails = get_admin_emails
      admin_emails.each do |email|
        AdminNotificationMailer.dealer_action(email, dealer.full_name, "created", "New dealer registered").deliver_later
      end
    end

    def notify_admins_about_dealer_action(dealer, action, details = nil)
      admin_emails = get_admin_emails
      admin_emails.each do |email|
        AdminNotificationMailer.dealer_action(email, dealer.full_name, action, details).deliver_later
      end
    end

    def require_admin_approver!
      return if current_admin&.approver_admin?
      render json: { error: "Only Super Admin or Sub Admin can approve dealer onboarding" }, status: :forbidden
    end

    def current_admin
      current_user
    end
  end
end
