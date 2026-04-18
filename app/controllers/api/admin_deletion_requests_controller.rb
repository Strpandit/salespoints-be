module Api
  class AdminDeletionRequestsController < ApplicationController
    before_action :require_admin
    before_action :require_super_admin!
    before_action :set_request, only: [:approve, :reject]

    def index
      scope = AdminDeletionRequest.includes(:admin_user, :reviewed_by_admin).order(requested_at: :desc)
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
      user = @request.admin_user
      return render json: { error: "Admin missing" }, status: :not_found unless user
      return render json: { error: "Cannot remove super admin this way" }, status: :forbidden if user.is_super_admin?

      @request.update!(
        status: "approved",
        reviewed_at: Time.current,
        reviewed_by_admin_id: current_admin.id
      )

      user.update!(status: "inactive")

      render json: { message: "Admin access removed" }, status: :ok
    end

    def reject
      reason = params[:rejection_reason].to_s.presence || "Request rejected by super administrator."

      @request.update!(
        status: "rejected",
        reviewed_at: Time.current,
        reviewed_by_admin_id: current_admin.id,
        rejection_reason: reason
      )

      NotificationService.deliver(
        recipient: @request.admin_user,
        actor: current_admin,
        notifiable: @request,
        kind: "admin_deletion_rejected",
        title: "Deletion request not approved",
        message: reason,
        payload: { admin_deletion_request_id: @request.id }
      )

      render json: { message: "Request rejected", data: serialize_request(@request.reload) }, status: :ok
    end

    private

    def require_super_admin!
      return if current_admin.super_admin?

      render json: { error: "Only super admin" }, status: :forbidden
    end

    def set_request
      @request = AdminDeletionRequest.find_by(id: params[:id])
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
        admin_user: r.admin_user ? { id: r.admin_user.id, email: r.admin_user.email, full_name: r.admin_user.full_name } : nil
      }
    end
  end
end
