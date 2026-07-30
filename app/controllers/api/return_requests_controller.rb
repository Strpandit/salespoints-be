module Api
  class ReturnRequestsController < ApplicationController
    def index
      requestable = find_requestable
      return render json: { error: "Order not found" }, status: :not_found unless requestable

      unless can_view_request?(requestable)
        return render json: {
          error: "You are not allowed to view these replacement requests"
        }, status: :forbidden
      end

      render json: {
        data: ReturnRequestSerializer.render(requestable.return_requests.recent),
        message: "Replacement requests fetched successfully"
      }, status: :ok
    end

    def create
      return render json: { error: "Admins can only view replacement requests" }, status: :forbidden if current_admin.present?

      requestable = find_requestable
      return render json: { error: "Order not found" }, status: :not_found unless requestable

      unless can_create_request_for?(requestable)
        return render json: { error: "You are not allowed to create replacement request for this order" }, status: :forbidden
      end

      unless replacement_request_params[:request_type].to_s == "replacement"
        return render json: { error: "Only replacement requests are allowed" }, status: :unprocessable_entity
      end

      unless requestable.payment_completed?
        return render json: { error: "Payment must be completed before requesting replacement" }, status: :unprocessable_entity
      end

      unless requestable.delivered?
        return render json: { error: "Order must be delivered before requesting replacement" }, status: :unprocessable_entity
      end

      unless requestable.replacement_window_open?
        return render json: { error: "Replacement window has expired" }, status: :unprocessable_entity
      end

      if requestable.replacement_requested?
        return render json: { error: "Replacement request already exists for this order" }, status: :unprocessable_entity
      end

      reason = replacement_request_params[:reason].to_s.strip

      if reason.length < 20
        return render json: {
          error: "Please provide a detailed replacement reason (minimum 20 characters)"
        }, status: :unprocessable_entity
      end

      unless requestable.can_transition_to?("replacement_requested")
        return render json: {
          error: "Order cannot be moved to replacement requested"
        }, status: :unprocessable_entity
      end

      request = nil

      ActiveRecord::Base.transaction do
        request = requestable.return_requests.create!(
          requester: current_user,
          request_type: "replacement",
          status: "requested",
          reason: replacement_request_params[:reason],
          details: replacement_request_params[:details],
          refund_amount: 0,
          seller_adjustment_amount: 0
        )

        if replacement_request_params[:media].present?
          request.media.attach(replacement_request_params[:media])
        end

        requestable.update!(status: :replacement_requested)
      end

      render json: {
        data: ReturnRequestSerializer.render(request),
        message: "Replacement request created successfully"
      }, status: :created
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def update
      return render json: { error: "Admins can only view replacement requests" }, status: :forbidden if current_admin.present?

      requestable = find_requestable
      return render json: { error: "Order not found" }, status: :not_found unless requestable

      unless can_manage_request?(requestable)
        return render json: { error: "You are not allowed to manage this replacement request" }, status: :forbidden
      end

      request = requestable.return_requests.find_by(id: params[:id])
      return render json: { error: "Replacement request not found" }, status: :not_found unless request

      unless request.replacement_request?
        return render json: {
          error: "Only replacement requests can be updated"
        }, status: :unprocessable_entity
      end

      unless request.open?
        return render json: {
          error: "Replacement request is already closed"
        }, status: :unprocessable_entity
      end

      updated_request = ReturnRequestTransitionService.new(
        return_request: request,
        actor: current_user,
        resolution_notes: params[:resolution_notes]
      ).transition!(next_status: params[:status])

      render json: {
        data: ReturnRequestSerializer.render(updated_request),
        message: "Replacement request updated successfully"
      }, status: :ok

    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def replacement_request_params
      params.permit(:request_type, :reason, :details, media: [])
    end

    def find_requestable
      case params[:order_type].to_s
      when "b2b"
        B2bOrder.find_by(id: params[:order_id])
      else
        Order.find_by(id: params[:order_id])
      end
    end

    def can_create_request_for?(requestable)
      return false if current_user.blank?

      case requestable
      when Order
        current_account.present? &&
          requestable.buyer_type == "Account" &&
          requestable.buyer_id == current_account.id

      when B2bOrder
        current_dealer.present? &&
          requestable.buyer_dealer_id == current_dealer.id

      else
        false
      end
    end

    def can_manage_request?(requestable)
      return false unless current_dealer.present?

      case requestable
      when Order
        requestable.seller_dealer_id == current_dealer.id

      when B2bOrder
        requestable.seller_dealer_id == current_dealer.id

      else
        false
      end
    end

    def can_view_request?(requestable)
      can_create_request_for?(requestable) ||
        can_manage_request?(requestable)
    end
  end
end
