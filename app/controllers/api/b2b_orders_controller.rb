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
                  .where.not(status: "pending")
                  .includes(:buyer_dealer, :seller_dealer, b2b_order_items: { dealer_product: :dealer })
                  .distinct
                  .order(created_at: :desc)
        else
          current_dealer.buyer_b2b_orders.includes(:buyer_dealer, :seller_dealer, b2b_order_items: { dealer_product: :dealer }).order(created_at: :desc)
        end

      paginated = orders.respond_to?(:page) ? orders.page(params[:page]).per(params[:per_page] || 20) : Kaminari.paginate_array(orders).page(params[:page]).per(params[:per_page] || 20)
      render json: serialize_resource(paginated, B2bOrderSerializer).merge(
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

    def place_from_cart
      cart = current_dealer.cart
      return render json: { error: "Cart is empty" }, status: :unprocessable_entity if cart.blank? || cart.cart_items.empty?

      buyer_latitude = params[:latitude].presence&.to_f
      buyer_longitude = params[:longitude].presence&.to_f
      if buyer_latitude.blank? || buyer_longitude.blank?
        return render json: { error: "Current location is required to place nearby B2B request" }, status: :unprocessable_entity
      end

      radius = params[:radius_km].to_i
      radius = 10 if radius <= 0

      payment_method = params[:payment_method].to_s.presence || "cod"

      if payment_method == "online"
        result = OnlinePaymentAttemptService.new(
          cart: cart,
          buyer: current_dealer,
          billing_address: {},
          shipping_address: {},
          context: "b2b_request",
          metadata: {
            latitude: buyer_latitude,
            longitude: buyer_longitude,
            radius_km: radius
          }
        ).call

        return render json: {
          data: {
            payment_attempt_id: result.attempt.id,
            attempt_number: result.attempt.attempt_number,
            amount: result.attempt.amount.to_f,
            status: result.attempt.status
          },
          payment: result.payment_data,
          clears_cart: false,
          message: "Online payment initiated. Your B2B request will be broadcast only after successful payment."
        }, status: :ok
      end

      order = B2bOrderCreationService.new(
        buyer: current_dealer,
        cart: cart,
        latitude: buyer_latitude,
        longitude: buyer_longitude,
        radius_km: radius,
        payment_method: payment_method,
        payment_status: payment_method == "cod" ? "pending" : "paid"
      ).call

      render json: serialize_resource(order, B2bOrderSerializer).merge(message: "B2B request broadcasted to matching nearby dealers"), status: :created
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def accept
      order = B2bOrder.where(status: ["pending", "partially_accepted"]).find_by(id: params[:id])
      return render json: { error: "Order request not found or already processed" }, status: :not_found unless order

      requested_ids = Array(params[:item_ids]).map(&:to_i).uniq
      offer = matching_open_offer(order: order, requested_ids: requested_ids)
      B2bOrderDealerResponseService.new(order: order, dealer: current_dealer, requested_ids: requested_ids, offer: offer).accept!

      render json: { message: "B2B items accepted successfully" }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def reject
      order = B2bOrder.where(status: ["pending", "partially_accepted"]).find_by(id: params[:id])
      return render json: { error: "Order request not found or already processed" }, status: :not_found unless order

      requested_ids = Array(params[:item_ids]).map(&:to_i).uniq
      offer = matching_open_offer(order: order, requested_ids: requested_ids)
      rejected_count = B2bOrderDealerResponseService.new(order: order, dealer: current_dealer, requested_ids: requested_ids, offer: offer).reject!

      render json: { message: "#{rejected_count} B2B item(s) rejected for this dealer" }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def require_dealer!
      return if current_dealer.present?

      render json: { error: "Dealer only" }, status: :unauthorized
    end

    def incoming_order_scope
      offers = current_dealer.b2b_order_offers.open_state.includes(b2b_order: [:buyer_dealer, :seller_dealer, { b2b_order_items: { dealer_product: :dealer } }]).order(created_at: :desc)
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

    def matching_open_offer(order:, requested_ids:)
      offers = order.b2b_order_offers.where(dealer: current_dealer, status: "open").order(created_at: :desc)
      return offers.first if requested_ids.blank?

      offers.find { |offer| (offer.item_id_values & requested_ids).any? }
    end
  end
end
