module Api
  class ReturnRequestsController < ApplicationController
    def index
      order = scoped_orders.find_by(id: params[:order_id])
      return render json: { error: "Order not found" }, status: :not_found unless order

      render json: {
        data: ReturnRequestSerializer.render(order.return_requests.recent),
        message: "Return requests fetched successfully"
      }, status: :ok
    end

    def create
      order = scoped_orders.find_by(id: params[:order_id])
      return render json: { error: "Order not found" }, status: :not_found unless order
      return render json: { error: "You are not allowed to request return/replacement for this order" }, status: :forbidden unless can_create_request_for?(order)
      return render json: { error: "An active return/replacement request already exists" }, status: :unprocessable_entity if order.active_return_request?
      return render json: { error: "Order must be delivered before requesting return or replacement" }, status: :unprocessable_entity unless order.delivered?
      return render json: { error: "Return window has closed for this order" }, status: :unprocessable_entity unless order.return_window_open? || current_admin.present?

      request_type = params[:request_type].to_s
      return render json: { error: "Invalid request type" }, status: :unprocessable_entity unless ReturnRequest::REQUEST_TYPES.include?(request_type)

      request = order.return_requests.create!(
        requester: current_user,
        request_type: request_type,
        status: "requested",
        reason: params[:reason],
        details: params[:details],
        refund_amount: request_type == "return" ? order.refundable_amount_remaining : 0,
        seller_adjustment_amount: request_type == "return" ? order.refundable_amount_remaining : 0
      )

      order.update!(status: request_type == "return" ? "return_requested" : "replacement_requested")

      render json: {
        data: ReturnRequestSerializer.render(request),
        message: "#{request_type.humanize} request created successfully"
      }, status: :created
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def update
      order = manageable_orders.find_by(id: params[:order_id])
      return render json: { error: "Order not found" }, status: :not_found unless order

      request = order.return_requests.find_by(id: params[:id])
      return render json: { error: "Return request not found" }, status: :not_found unless request

      updated_request = ReturnRequestTransitionService.new(
        return_request: request,
        actor: current_user,
        resolution_notes: params[:resolution_notes],
        refund_amount: params[:refund_amount]
      ).transition!(next_status: params[:status])

      render json: {
        data: ReturnRequestSerializer.render(updated_request),
        order: OrderSerializer.render(order.reload),
        message: "Return request updated successfully"
      }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def scoped_orders
      if current_admin
        Order.all
      elsif current_dealer
        Order.where(buyer: current_dealer).or(Order.where(seller_dealer_id: current_dealer.id))
      elsif current_account
        current_account.orders
      else
        Order.none
      end
    end

    def manageable_orders
      if current_admin
        Order.all
      elsif current_dealer
        Order.where(seller_dealer_id: current_dealer.id)
      else
        Order.none
      end
    end

    def can_create_request_for?(order)
      return true if current_admin.present?
      return false if current_user.blank?

      order.buyer_type == current_user.class.name && order.buyer_id == current_user.id
    end
  end
end
