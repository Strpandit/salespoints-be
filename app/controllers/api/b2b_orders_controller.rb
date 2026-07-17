module Api
  class B2bOrdersController < ApplicationController
    before_action :require_dealer!

    def index
      view = params[:view].to_s

      orders =
        case view
        when "incoming"
          incoming_order_scope
        when "accepted"
          current_dealer.seller_b2b_orders
                        .where("request_status = ? OR (request_status IS NULL AND status IN (?))", "accepted_request", %w[paid confirmed shipped delivered])
                        .includes(:buyer_dealer, :seller_dealer, b2b_order_items: { dealer_product: :dealer })
                        .order(created_at: :desc)
        else
          current_dealer.buyer_b2b_orders
                        .where("request_status IS NULL OR status IN (?)", %w[pending_request pending_payment paid confirmed shipped delivered])
                        .includes(:buyer_dealer, :seller_dealer, b2b_order_items: { dealer_product: :dealer })
                        .order(created_at: :desc)
        end

      paginated = orders.respond_to?(:page) ? orders.page(params[:page]).per(params[:per_page] || 20) : Kaminari.paginate_array(orders).page(params[:page]).per(params[:per_page] || 20)
      render json: serialize_resource(paginated, B2bOrderSerializer, base_url: request.base_url).merge(
        meta: {
          current_page: paginated.current_page,
          next_page: paginated.next_page,
          prev_page: paginated.prev_page,
          total_pages: paginated.total_pages,
          total_count: paginated.total_count
        },
        message: "B2B orders fetched successfully"
      ), status: :ok
    end

    def place_direct
      buyer_latitude = params[:latitude].presence&.to_f
      buyer_longitude = params[:longitude].presence&.to_f
      if buyer_latitude.blank? || buyer_longitude.blank?
        return render json: { error: "Current location is required to place B2B request" }, status: :unprocessable_entity
      end

      radius = params[:radius_km].to_i
      radius = 5 if radius <= 0
      payment_method = params[:payment_method].to_s.presence || "cod"

      order = B2bDirectOrderService.new(
        buyer: current_dealer,
        dealer_product_id: params[:dealer_product_id],
        quantity: params[:quantity],
        latitude: buyer_latitude,
        longitude: buyer_longitude,
        radius_km: radius,
        payment_method: payment_method,
        payment_status: payment_method == "cod" ? "pending" : "paid"
      ).call

      render json: serialize_resource(order, B2bOrderSerializer, base_url: request.base_url).merge(
        message: "Request sent to nearby dealers"
      ), status: :created
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def accept
      order = B2bOrder.find_by(id: params[:id], seller_dealer_id: current_dealer.id)
      return render json: { error: "Request not found or already processed" }, status: :not_found unless order

      unless acceptable_order?(order)
        return render json: { error: "Request not available for acceptance" }, status: :unprocessable_entity
      end

      offer = matching_open_offer(order: order)

      B2bOrderDealerResponseService.new(
        order: order,
        dealer: current_dealer,
        offer: offer
      ).accept!

      render json: { message: "Order accepted successfully." }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def reject
      order = B2bOrder.find_by(id: params[:id], seller_dealer_id: current_dealer.id)
      return render json: { error: "Request not found or already processed" }, status: :not_found unless order

      unless acceptable_order?(order)
        return render json: { error: "Request not available for rejection" }, status: :unprocessable_entity
      end

      offer = matching_open_offer(order: order)

      B2bOrderDealerResponseService.new(
        order: order,
        dealer: current_dealer,
        offer: offer
      ).reject!

      render json: { message: "Order rejected successfully" }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def payment
      order = current_dealer.buyer_b2b_orders.find_by(id: params[:id])
      return render json: { error: "Order not found" }, status: :not_found unless order

      if order.status == "confirmed"
        return render json: {
          message: "Order already confirmed",
          order: B2bOrderSerializer.render(order, base_url: request.base_url),
          payment_status: "confirmed"
        }, status: :ok
      end

      unless order.pending_request? || order.pending_payment?
        return render json: { 
          error: "Order is not ready for payment. Current status: #{order.status}",
        }, status: :unprocessable_entity
      end

      payment_method = params[:payment_method].to_s.presence || "cod"

      unless B2bOrder::PAYMENT_METHODS.include?(payment_method)
        return render json: { error: "Invalid payment method" }, status: :unprocessable_entity
      end

      result = B2bOrderPaymentService.new(
        order_id: order.id,
        payment_method: payment_method
      ).call

      if payment_method == "cod"
        render json: {
          message: "Order confirmed with COD",
          order: B2bOrderSerializer.render(result[:order], base_url: request.base_url),
          payment_status: "confirmed"
        }, status: :ok
      else
        render json: {
          message: "Payment initiated",
          order: B2bOrderSerializer.render(result[:order], base_url: request.base_url),
          payment_data: result[:payment_data],
          payment_status: "pending"
        }, status: :ok
      end
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def update_status
      order = current_dealer.seller_b2b_orders.includes(:delivery_confirmation).find_by(id: params[:id])
      return render json: { error: "Order not found" }, status: :not_found unless order

      next_status = params[:status].to_s
      return render json: { error: "Status is required" }, status: :unprocessable_entity if next_status.blank?
      return render json: { error: "Delivered status will be set automatically after delivery proof verification" }, status: :unprocessable_entity if next_status == "delivered"
      return render json: { error: "Invalid status transition" }, status: :unprocessable_entity unless order.can_transition_to?(next_status)

      case next_status
      when "shipped"
        order.mark_shipped!(note: params[:status_note])
        delivery_confirmation = DeliveryConfirmationService.new(deliverable: order, actor: current_dealer).create_or_refresh!
      else
        return render json: { error: "Unsupported status update" }, status: :unprocessable_entity
      end

      render json: serialize_resource(order.reload, B2bOrderSerializer, include: [:delivery_confirmation], base_url: request.base_url).merge(
        delivery_confirmation: delivery_confirmation ? DeliveryConfirmationSerializer.render(delivery_confirmation) : nil,
        message: "B2B order updated successfully"
      ), status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def require_dealer!
      return if current_dealer.present?

      render json: { error: "Dealer only" }, status: :unauthorized
    end

    def incoming_order_scope
      offers = current_dealer.b2b_order_offers.open_state
                             .includes(b2b_order: [:buyer_dealer, :seller_dealer, { b2b_order_items: { dealer_product: :dealer } }])
                             .order(created_at: :desc)

      orders = {}

      offers.each do |offer|
        order = offer.b2b_order
        visible_ids = offer.item_id_values
        visible_items = order.b2b_order_items.select { |item| visible_ids.include?(item.id) }
        order.define_singleton_method(:b2b_order_items) { visible_items }
        orders[order.id] ||= order
      end

      orders.values.sort_by(&:created_at).reverse
    end

    def acceptable_order?(order)
      return false unless order.request_status == "pending_request"
      if order.is_direct_buy? && order.source_type == "WholesalerPost"
        order.status.in?(%w[pending_request pending_payment])
      else
        order.status.in?(%w[pending_request pending_payment])
      end
    end

    def matching_open_offer(order:)
      order.b2b_order_offers.where(dealer: current_dealer, status: "open").order(created_at: :desc).first
    end
  end
end
