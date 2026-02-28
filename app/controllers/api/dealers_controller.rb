module Api
  class DealersController < ApplicationController
    before_action :authenticate_request!
    before_action :require_admin, only: [:create, :index, :active_dealers, :block, :unblock, :destroy, :approve, :reject]
    before_action :set_dealer, only: [:show, :update, :block, :unblock, :approve, :reject]
    before_action :authorize_dealer_update, only: [:update, :show]

    def index
      dealers = Dealer.where(status: "pending").includes(:dealer_profile, :dealer_location)
      render json: {
        data: ActiveModelSerializers::SerializableResource.new(dealers, each_serializer: DealerSerializer),
        message: "Dealers fetched successfully"
      }, status: :ok
    end

    def active_dealers
      dealers = Dealer.active.includes(:dealer_profile, :dealer_location)
      render json: {
        data: ActiveModelSerializers::SerializableResource.new(dealers, each_serializer: DealerSerializer),
        message: "Active dealers fetched successfully"
      }, status: :ok
    end

    def create
      dealer = Dealer.new(dealer_params)

      if dealer.save
        # Generate temporary password and send welcome email
        temp_password = SecureRandom.hex(6)
        dealer.update(password: temp_password, password_confirmation: temp_password)
        
        # Send welcome email to dealer
        DealerMailer.welcome_email(dealer, temp_password).deliver_later
        
        # Notify admins about new dealer creation
        notify_admins_about_dealer_creation(dealer)
        
        render json: {
          data: DealerSerializer.new(dealer),
          message: "Dealer created successfully. Welcome email sent."
        }, status: :created
      else
        render json: { error: dealer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def show
      render json: {
        data: DealerSerializer.new(@dealer),
        message: "Dealer fetched successfully"
      }, status: :ok
    end

    def update
      if @dealer.update(dealer_params)
        render json: { data: DealerSerializer.new(@dealer), message: "Dealer updated successfully" }, status: :ok
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

      if @dealer.update(status: "active")
        # Send approval email to dealer
        DealerMailer.approval_email(@dealer).deliver_later
        
        # Notify admins about approval
        notify_admins_about_dealer_action(@dealer, "approved")
        
        render json: {
          data: DealerSerializer.new(@dealer),
          message: "Dealer approved successfully. Approval email sent."
        }, status: :ok
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
        # Send rejection email to dealer
        DealerMailer.rejection_email(@dealer, rejection_reason).deliver_later
        
        # Notify admins about rejection
        notify_admins_about_dealer_action(@dealer, "rejected", rejection_reason)
        
        render json: {
          data: DealerSerializer.new(@dealer),
          message: "Dealer rejected successfully. Rejection email sent."
        }, status: :ok
      else
        render json: { error: @dealer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @dealer.destroy
      render json: { message: "Dealer deleted successfully" }, status: :ok
    end

    private

    def dealer_params
      params.require(:dealer).permit(
        :first_name, :last_name, :email, :phone, :gender, :country_code, :status, :password, :password_confirmation,
        dealer_profile_attributes: [
          :business_name, :business_type, :gst_number, :pan_number, :aadhar_number,
          :bank_name, :bank_account_number, :ifsc_code, :business_address,
          :business_contact_number, :business_email, :is_verified
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
      AdminUser.where(is_super_admin: true).pluck(:email)
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
  end
end