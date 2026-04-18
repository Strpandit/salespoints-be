module Api
  class OrdersController < ApplicationController
    def index
      orders = scoped_orders
      orders = apply_filters(orders)
      paginated = orders.recent.page(params[:page]).per(params[:per_page] || 20)

      render json: serialize_resource(paginated, OrderSerializer).merge(
        meta: pagination_meta(paginated),
        pagination: pagination_meta(paginated),
        message: "Orders fetched successfully"
      ), status: :ok
    end

    def show
      order = scoped_orders.includes(order_items: [:dealer_product, :product_variant]).find_by(id: params[:id])
      return render json: { error: "Order not found" }, status: :not_found unless order

      render json: serialize_resource(order, OrderSerializer).merge(
        message: "Order fetched successfully"
      ), status: :ok
    end

    def update
      order = scoped_orders.find_by(id: params[:id])
      return render json: { error: "Order not found" }, status: :not_found unless order
      return render json: { error: "You are not allowed to update this order" }, status: :forbidden unless can_update_order?(order)

      next_status = params[:status].to_s
      return render json: { error: "Status is required" }, status: :unprocessable_entity if next_status.blank?
      return render json: { error: "Invalid status transition" }, status: :unprocessable_entity unless order.can_transition_to?(next_status)

      attrs = { status: next_status, status_note: params[:status_note] }
      attrs[:processing_at] = Time.current if next_status == "processing"
      attrs[:shipped_at] = Time.current if next_status == "shipped"
      attrs[:delivered_at] = Time.current if next_status == "delivered"
      attrs[:cancelled_at] = Time.current if next_status == "cancelled"

      order.update!(attrs.compact)
      OrderNotificationJob.perform_later(order.id, "status_updated", current_user.class.name, current_user.id)

      render json: serialize_resource(order.reload, OrderSerializer).merge(
        message: "Order updated successfully"
      ), status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def scoped_orders
      if current_admin
        Order.includes(:buyer, :seller_dealer, order_items: [:dealer_product, :product_variant])
      elsif current_dealer
        view = params[:view].to_s
        if view == "sales"
          current_dealer.sales_orders
                        .joins(:order_items)
                        .merge(OrderItem.joins(:dealer_product).where(dealer_products: { dealer_id: current_dealer.id }))
                        .includes(:buyer, :seller_dealer, order_items: [:dealer_product, :product_variant])
                        .distinct
        else
          current_dealer.orders.includes(:buyer, :seller_dealer, order_items: [:dealer_product, :product_variant])
        end
      elsif current_account
        current_account.orders.includes(:buyer, :seller_dealer, order_items: [:dealer_product, :product_variant])
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
  end
end
