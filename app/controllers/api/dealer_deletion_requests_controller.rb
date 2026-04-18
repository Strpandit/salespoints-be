module Api
  class DealerDeletionRequestsController < ApplicationController
    before_action :require_admin
    before_action :check_dealers_permission!
    before_action :set_request, only: [:approve, :reject]

    def index
      scope = DealerDeletionRequest.includes(:dealer, :reviewed_by_admin).order(requested_at: :desc)
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
      dealer = @request.dealer
      return render json: { error: "Dealer missing" }, status: :not_found unless dealer

      @request.update!(
        status: "approved",
        reviewed_at: Time.current,
        reviewed_by_admin_id: current_admin.id
      )

      dealer.destroy
      unless dealer.destroyed?
        @request.update_columns(status: "pending", reviewed_at: nil, reviewed_by_admin_id: nil)
        return render json: { error: "Unable to delete dealer" }, status: :unprocessable_entity
      end

      render json: { message: "Dealer deleted" }, status: :ok
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
        recipient: @request.dealer,
        actor: current_admin,
        notifiable: @request,
        kind: "dealer_deletion_rejected",
        title: "Dealer deletion not approved",
        message: reason,
        payload: { dealer_deletion_request_id: @request.id }
      )

      render json: { message: "Request rejected", data: serialize_request(@request.reload) }, status: :ok
    end

    private

    def require_admin
      render json: { error: "Admin only" }, status: :unauthorized unless current_user_type == "AdminUser"
    end

    def check_dealers_permission!
      unless current_admin.can_access?(:dealers, :write)
        render json: { error: "You do not have permission to manage dealer deletion requests" }, status: :forbidden
      end
    end

    def set_request
      @request = DealerDeletionRequest.find_by(id: params[:id])
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
        dealer: r.dealer ? { id: r.dealer.id, email: r.dealer.email, full_name: r.dealer.full_name, dealer_code: r.dealer.dealer_code } : nil
      }
    end
  end
end
