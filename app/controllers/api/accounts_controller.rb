module Api
  class AccountsController < ApplicationController
    before_action :authenticate_request!
    before_action :require_admin, only: [:index, :block, :unblock]
    before_action :check_permission, only: [:index, :block, :unblock]
    before_action :set_account, only: [:show, :update, :destroy, :block, :unblock, :request_deletion, :cancel_deletion_request]
    before_action :authorize_account!, only: [:show, :update, :request_deletion, :cancel_deletion_request]

    def index
      @accounts = Account.all.order(created_at: :desc)

      if params[:status].present? && params[:status] != "all"
        @accounts = @accounts.where(status: params[:status])
      end

      if params[:email_verified].present? && params[:email_verified] != "all"
        is_ver = ActiveModel::Type::Boolean.new.cast(params[:email_verified])
        @accounts = @accounts.where(email_verified: is_ver)
      end

      if params[:date_from].present?
        from = Date.parse(params[:date_from]).beginning_of_day rescue nil
        @accounts = @accounts.where("created_at >= ?", from) if from
      end

      if params[:date_to].present?
        to = Date.parse(params[:date_to]).end_of_day rescue nil
        @accounts = @accounts.where("created_at <= ?", to) if to
      end

      if params[:search].present?
        search = "%#{params[:search].strip.downcase}%"

        @accounts = @accounts.where(
          "LOWER(first_name) LIKE :search
          OR LOWER(last_name) LIKE :search
          OR LOWER(email) LIKE :search
          OR phone LIKE :search",
          search: search
        )
      end

      case params[:sort_by]
      when "oldest"
        @accounts = @accounts.order(created_at: :asc)
      when "name_asc"
        @accounts = @accounts.order(first_name: :asc)
      when "name_desc"
        @accounts = @accounts.order(first_name: :desc)
      else
        @accounts = @accounts.order(created_at: :desc)
      end

      @accounts = @accounts.page(params[:page]).per(params[:per_page] || 20)
      if @accounts.exists?
        render json: serialize_resource(@accounts, AccountSerializer).merge(
          meta: {
            current_page: @accounts.current_page,
            next_page: @accounts.next_page,
            prev_page: @accounts.prev_page,
            total_pages: @accounts.total_pages,
            total_count: @accounts.total_count,
            statuses: ["all"] + Account.statuses.keys
          },
          message: 'Account list fetched successfully'
        ), status: :ok
      else
        render json: { message: "No Data Found." }, status: :not_found
      end
    end

    def show
      render json: serialize_resource(@account, AccountSerializer).merge(
        message: 'User Details'
      ), status: :ok
    end

    def update
      if @account.update(account_params)
        render json: { account: serialize_data(@account, AccountSerializer), message: "Account updated successfully" }, status: :ok
      else
        render json: { errors: @account.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      render json: {
        message: "Account deletion requires admin approval. Submit a request from Security settings in your profile."
      }, status: :forbidden
    end

    def request_deletion
      unless params[:password].present?
        return render json: { message: "Password is required" }, status: :unprocessable_entity
      end

      unless @account.authenticate(params[:password])
        return render json: { message: "Incorrect password" }, status: :unauthorized
      end

      if @account.account_deletion_requests.pending.exists?
        return render json: { message: "A deletion request is already pending review" }, status: :unprocessable_entity
      end

      req = @account.account_deletion_requests.create!(
        status: "pending",
        reason: params[:reason].to_s.presence,
        requested_at: Time.current,
        password_verified_at: Time.current
      )

      AdminUser.find_each do |admin|
        next unless admin.can_access?(:accounts, :read)

        NotificationService.deliver(
          recipient: admin,
          actor: @account,
          notifiable: req,
          kind: "account_deletion_requested",
          title: "Account deletion requested",
          message: "#{@account.full_name.presence || 'Customer'} (#{@account.email}) requested account deletion.",
          payload: { account_deletion_request_id: req.id, account_id: @account.id }
        )
      end

      render json: {
        message: "Deletion request submitted. An administrator will review it.",
        data: { pending_deletion_request: true }
      }, status: :ok
    end

    def cancel_deletion_request
      req = @account.account_deletion_requests.pending.order(created_at: :desc).first
      return render json: { message: "No pending deletion request" }, status: :not_found unless req

      req.destroy!
      render json: { message: "Deletion request cancelled", data: { pending_deletion_request: false } }, status: :ok
    end

    def block
      @account.update!(status: 'banned')
      
      # Send account blocked email
      AccountMailer.account_blocked(@account).deliver_later if @account.email.present?
      
      render json: { message: "Account blocked successfully" }, status: :ok
    end

    def unblock
      @account.update!(status: 'active')
      
      # Send account unblocked email
      AccountMailer.account_unblocked(@account).deliver_later if @account.email.present?
      
      render json: { message: "Account unblocked successfully" }, status: :ok
    end

    def change_password
      unless current_account.authenticate(params[:current_password])
        return unauthorized("Incorrect current password")
      end

      if current_account.update(
        password: params[:new_password],
        password_confirmation: params[:confirm_password]
      )
        render json: { status: 200, message: "Password changed successfully" }, status: :ok
      else
        render json: { error: current_account.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def set_account
      @account = Account.find(params[:id])
    end

    def authorize_account!
      unless current_account && current_account.id == @account.id
        render json: { error: 'Not authorized' }, status: :forbidden
      end
    end

    def account_params
      params.require(:account).permit(:first_name, :last_name, :email, :phone, :country_code, :gender, :status, :password, :password_confirmation, :google_signup)
    end

    def check_permission
      unless current_admin.can_access?(:accounts)
        render json: { error: "You do not have permission to manage customers"}, status: :forbidden
      end
    end

    def require_admin
      render json: { error: "Admin only" }, status: :unauthorized unless current_user_type == "AdminUser"
    end

    def current_admin
      current_user
    end
  end
end
