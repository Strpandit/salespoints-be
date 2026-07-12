module Api
  class OrdersController < ApplicationController
    before_action :require_buyer!, only: [:buy_now]

    def buy_now
      billing_address = params[:billing_address].presence || checkout_address_payload
      shipping_address = params[:shipping_address].presence || checkout_address_payload
      payment_method = params[:payment_method].to_s.presence || "cod"

      result = DirectBuyNowService.new(
        buyer: current_buyer,
        dealer_product_id: params[:dealer_product_id],
        product_variant_id: params[:product_variant_id],
        quantity: params[:quantity] || 1,
        payment_method: payment_method,
        billing_address: billing_address,
        shipping_address: shipping_address
      ).call

      primary_order = result.orders.first
      render json: {
        data: serialize_data(primary_order, OrderSerializer),
        order: serialize_data(primary_order, OrderSerializer),
        payment: result.payment_data,
        message: "Order placed successfully"
      }, status: :created
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def index
      orders = scoped_orders
      orders = apply_filters(orders)
      paginated = orders.recent.page(params[:page]).per(params[:per_page] || 20)
      paginated.each { |order| OrderSettlementService.process_if_due!(order) }

      render json: serialize_resource(paginated, OrderSerializer, base_url: request.base_url).merge(
        meta: pagination_meta(paginated),
        pagination: pagination_meta(paginated),
        message: "Orders fetched successfully"
      ), status: :ok
    end

    def show
      order = scoped_orders.includes(order_items: :product_variant).find_by(id: params[:id])
      return render json: { error: "Order not found" }, status: :not_found unless order
      OrderSettlementService.process_if_due!(order)

      render json: serialize_resource(order, OrderSerializer, include: [:order_items, :return_requests], base_url: request.base_url).merge(
        message: "Order fetched successfully"
      ), status: :ok
    end

    def update
      order = scoped_orders.includes(:delivery_confirmation).find_by(id: params[:id])
      return render json: { error: "Order not found" }, status: :not_found unless order
      return render json: { error: "You are not allowed to update this order" }, status: :forbidden unless can_update_order?(order)

      next_status = params[:status].to_s
      return render json: { error: "Status is required" }, status: :unprocessable_entity if next_status.blank?
      if next_status == "delivered"
        return render json: { error: "Delivered status will be set automatically after delivery form and dual OTP verification" }, status: :unprocessable_entity
      end

      OrderLifecycleService.new(order: order, actor: current_user, status_note: params[:status_note]).transition!(next_status: next_status)
      delivery_confirmation = nil
      if next_status == "shipped"
        delivery_confirmation = DeliveryConfirmationService.new(deliverable: order, actor: current_user).create_or_refresh!
      end
      OrderNotificationJob.perform_later(order.id, "status_updated", current_user.class.name, current_user.id)

      render json: serialize_resource(order.reload, OrderSerializer, include: [:delivery_confirmation], base_url: request.base_url).merge(
        delivery_confirmation: delivery_confirmation ? DeliveryConfirmationSerializer.render(delivery_confirmation) : nil,
        message: "Order updated successfully"
      ), status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def refund
      order = manageable_financial_orders.find_by(id: params[:id])
      return render json: { error: "Order not found" }, status: :not_found unless order

      refund_amount = params[:amount].presence || order.refundable_amount_remaining
      result = OrderRefundService.new(
        order: order,
        actor: current_user,
        amount: refund_amount,
        reason: params[:reason]
      ).call

      render json: {
        data: OrderSerializer.render(result.order, base_url: request.base_url),
        refund: result.refund_payload,
        dealer_balance: result.dealer_balance.to_f,
        message: "Refund initiated successfully"
      }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def release_settlement
      order = manageable_financial_orders.find_by(id: params[:id])
      return render json: { error: "Order not found" }, status: :not_found unless order

      result = OrderSettlementService.new(
        order: order,
        actor: current_user,
        force: ActiveModel::Type::Boolean.new.cast(params[:force])
      ).call

      render json: {
        data: OrderSerializer.render(result.order, base_url: request.base_url),
        released_amount: result.released_amount.to_f,
        dealer_balance: result.dealer_balance.to_f,
        message: "Settlement released successfully"
      }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def scoped_orders
      if current_admin
        Order.includes(:buyer, order_items: :product_variant)
      elsif current_dealer
        dealer_scope = params[:view].to_s == "sales" ? current_dealer.sales_orders : current_dealer.orders
        dealer_scope.includes(:buyer, order_items: :product_variant)
      elsif current_account
        current_account.orders.includes(:buyer, order_items: :product_variant)
      else
        Order.none
      end
    end

    def apply_filters(scope)
      filtered = scope
      status = params[:status].presence || params[:filter_status].presence
      filtered = filtered.where(status: status) if status.present?

      if params[:search].present?
        query = params[:search].strip
        filtered = filtered
                   .joins("LEFT JOIN accounts ON orders.buyer_type = 'Account' AND orders.buyer_id = accounts.id")
                   .joins("LEFT JOIN dealers buyers_dealers ON orders.buyer_type = 'Dealer' AND orders.buyer_id = buyers_dealers.id")
                   .where(
                     "orders.order_number ILIKE :q OR accounts.email ILIKE :q OR accounts.first_name ILIKE :q OR buyers_dealers.email ILIKE :q OR buyers_dealers.first_name ILIKE :q",
                     q: "%#{query}%"
                   )
      end

      filtered
    end

    def pagination_meta(records)
      {
        current_page: records.current_page,
        next_page: records.next_page,
        prev_page: records.prev_page,
        total_pages: records.total_pages,
        total_count: records.total_count
      }
    end

    def can_update_order?(order)
      return true if current_admin.present?
      return order.seller_dealer_id == current_dealer.id if current_dealer.present?

      false
    end

    def manageable_financial_orders
      return Order.all if current_admin
      return Order.where(seller_dealer_id: current_dealer.id) if current_dealer

      Order.none
    end

    def require_buyer!
      return if current_account.present? || current_dealer.present?

      render json: { error: "Authentication required" }, status: :unauthorized
    end

    def current_buyer
      current_account || current_dealer
    end

    def checkout_address_payload
      return {} unless current_account

      address = current_account.addresses.find_by(is_default: true) || current_account.addresses.order(created_at: :desc).first
      return {} if address.blank?

      {
        name: address.name,
        phone: address.phone,
        address_line1: address.address_line1,
        address_line2: address.address_line2,
        city: address.city,
        state: address.state,
        postal_code: address.postal_code,
        country: address.country
      }
    end
  end
end
