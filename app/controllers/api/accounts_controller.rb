module Api
  class AccountsController < ApplicationController
    before_action :authenticate_request!
    before_action :require_admin, only: [:index, :block, :unblock]
    before_action :check_permission, only: [:index, :block, :unblock]
    before_action :set_account, only: [:show, :update, :destroy, :block, :unblock]
    before_action :authorize_account!, only: [:show, :update, :destroy]

    def index
      @accounts = Account.all
      if @accounts.exists?
        render json: {
          data: ActiveModelSerializers::SerializableResource.new(@accounts, each_serializer: AccountSerializer),
          message: 'Account list fetched successfully'
        }, status: :ok
      else
        render json: { message: "No Data Found." }, status: :not_found
      end
    end

    def show
      render json: {
        data: AccountSerializer.new(@account).serializable_hash,
        message: 'User Details'
      }, status: :ok
    end

    def update
      if @account.update(account_params)
        render json: { account: AccountSerializer.new(@account), message: "Account updated successfully" }, status: :ok
      else
        render json: { errors: @account.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @account = Account.with_deleted.find_by(id: params[:id])

      return render json: { message: "Account not found" }, status: :not_found unless @account

      unless params[:password].present?
        return render json: { message: "Password is required" }, status: :unprocessable_entity
      end
      
      unless @account.authenticate(params[:password])
        return render json: { message: "Incorrect password" }, status: :unauthorized
      end

      # Store email before deletion
      account_email = @account.email

      if @account.destroy
        # Send account deletion email
        AccountMailer.account_deleted(account_email).deliver_later if account_email.present?
        
        render json: { message: "Account deleted successfully" }, status: :ok
      else
        render json: { message: "Unable to delete account" }, status: :unprocessable_entity
      end
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
      params.permit(:first_name, :last_name, :email, :phone, :country_code, :gender, :status, :password, :password_confirmation, :google_signup)
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
