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
          B2bOrder.joins(b2b_order_items: :dealer_product)
                  .where(dealer_products: { dealer_id: current_dealer.id })
                  .where(request_status: "accepted_request")
                  .where(status: "pending_payment")
                  .includes(:buyer_dealer, :seller_dealer, b2b_order_items: { dealer_product: :dealer })
                  .distinct
                  .order(created_at: :desc)
        else
          current_dealer.buyer_b2b_orders
                        .where("request_status IS NULL OR status IN (?)", %w[pending_request pending_payment])
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
      order = B2bOrder.pending_requests.find_by(id: params[:id])
      return render json: { error: "Request not found or already processed" }, status: :not_found unless order

      offer = matching_open_offer(order: order)

      B2bOrderDealerResponseService.new(
        order: order,
        dealer: current_dealer,
        offer: offer
      ).accept!

      render json: { message: "Order accepted successfully. Payment link sent to buyer." }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def reject
      order = B2bOrder.pending_requests.find_by(id: params[:id])
      return render json: { error: "Request not found or already processed" }, status: :not_found unless order

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

      unless order.pending_payment?
        return render json: { 
          error: "Order is not ready for payment. Current status: #{order.status}",
          current_status: order.status
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

    private

    def require_dealer!
      return if current_dealer.present?

      render json: { error: "Dealer only" }, status: :unauthorized
    end

    def incoming_order_scope
      offers = current_dealer.b2b_order_offers.open_state
                             .includes(b2b_order: [:buyer_dealer, :seller_dealer, { b2b_order_items: { dealer_product: :dealer } }])
                             .order(created_at: :desc)

      deduped = {}

      offers.each do |offer|
        order = offer.b2b_order
        visible_ids = offer.item_id_values
        visible_items = order.b2b_order_items.select { |item| visible_ids.include?(item.id) }
        order.define_singleton_method(:b2b_order_items) { visible_items }
        deduped[order.id] ||= order
      end

      deduped.values
    end

    def matching_open_offer(order:)
      order.b2b_order_offers.where(dealer: current_dealer, status: "open").order(created_at: :desc).first
    end
  end
end
