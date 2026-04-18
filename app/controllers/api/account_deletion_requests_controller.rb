module Api
  class AccountDeletionRequestsController < ApplicationController
    before_action :require_admin
    before_action :check_accounts_permission!
    before_action :set_request, only: [:approve, :reject]

    def index
      scope = AccountDeletionRequest.includes(:account, :reviewed_by_admin).order(requested_at: :desc)
      scope = scope.where(status: params[:status]) if params[:status].present?

      records = scope.page(params[:page]).per(params[:per_page] || 20)

      render json: {
        data: records.map { |r| serialize_request(r) },
        meta: {
          current_page: records.current_page,
          next_page: records.next_page,
          prev_page: records.prev_page,
          total_pages: records.total_pages,
          total_count: records.total_count
        }
      }, status: :ok
    end

    def approve
      account = @request.account
      return render json: { error: "Account missing" }, status: :not_found unless account

      account_email = account.email
      account.destroy
      if account.deleted_at.blank?
        return render json: { error: "Unable to delete account" }, status: :unprocessable_entity
      end

      AccountMailer.account_deleted(account_email).deliver_later if account_email.present?

      render json: { message: "Account deleted" }, status: :ok
    end

    def reject
      reason = params[:rejection_reason].to_s.presence || "Request rejected by administrator."

      @request.update!(
        status: "rejected",
        reviewed_at: Time.current,
        reviewed_by_admin_id: current_admin.id,
        rejection_reason: reason
      )

      NotificationService.deliver(
        recipient: @request.account,
        actor: current_admin,
        notifiable: @request,
        kind: "account_deletion_rejected",
        title: "Account deletion not approved",
        message: reason,
        payload: { account_deletion_request_id: @request.id }
      )

      render json: { message: "Request rejected", data: serialize_request(@request.reload) }, status: :ok
    end

    private

    def require_admin
      render json: { error: "Admin only" }, status: :unauthorized unless current_user_type == "AdminUser"
    end

    def check_accounts_permission!
      unless current_admin.can_access?(:accounts, :write)
        render json: { error: "You do not have permission to manage customer deletion requests" }, status: :forbidden
      end
    end

    def set_request
      @request = AccountDeletionRequest.find_by(id: params[:id])
      return render json: { error: "Not found" }, status: :not_found unless @request
      return render json: { error: "Already processed" }, status: :unprocessable_entity unless @request.status == "pending"
    end

    def serialize_request(r)
      {
        id: r.id,
        status: r.status,
        reason: r.reason,
        rejection_reason: r.rejection_reason,
        requested_at: r.requested_at,
        reviewed_at: r.reviewed_at,
        account: r.account ? { id: r.account.id, email: r.account.email, full_name: r.account.full_name } : nil
      }
    end
  end
end
