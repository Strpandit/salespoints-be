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

      paginated = orders.page(params[:page]).per(params[:per_page] || 20)
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

      order = nil
      ActiveRecord::Base.transaction do
        order = B2bOrder.create!(
          buyer_dealer_id: current_dealer.id,
          status: "pending",
          requested_radius_km: radius,
          latitude: buyer_latitude,
          longitude: buyer_longitude,
          subtotal_amount: cart.subtotal_amount,
          tax_amount: cart.tax_amount,
          discount_amount: cart.coupon_discount_amount,
          total_amount: cart.grand_total,
          coupon_code: cart.coupon_code,
          expires_at: 20.minutes.from_now
        )

        cart.cart_items.includes(:product_variant).find_each do |ci|
          B2bOrderItem.create!(
            b2b_order_id: order.id,
            product_variant_id: ci.product_variant_id,
            quantity: ci.quantity,
            unit_price: ci.unit_price,
            total_price: ci.total_price
          )
        end

        dealer_matches = eligible_nearby_dealers(order: order)
        raise StandardError, "No nearby dealers available within range" if dealer_matches.empty?

        dealer_matches.each do |dealer, matched_items|
          NotificationService.deliver(
            recipient: dealer,
            actor: current_dealer,
            notifiable: order,
            kind: "b2b_order_request",
            title: "New B2B bulk request nearby",
            message: "A nearby dealer is requesting #{matched_items.size} item(s). Respond fast to secure what you can fulfill.",
            visible_in_app: false,
            delivery_channels: { push: true, whatsapp: true, sms: false, email: false, in_app: false },
            payload: {
              order_id: order.id,
              buyer_dealer_id: current_dealer.id,
              buyer_name: current_dealer.dealer_code,
              total_amount: order.total_amount.to_f,
              requested_radius_km: radius,
              latitude: order.latitude,
              longitude: order.longitude,
              b2b_state: "open",
              item_ids: matched_items.map(&:id),
              items: serialize_b2b_items(matched_items)
            }
          )
        end

        cart.clear
        cart.remove_coupon!
      end

      render json: serialize_resource(order, B2bOrderSerializer).merge(
        message: "B2B request broadcasted to matching nearby dealers"
      ), status: :created
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def accept
      order = B2bOrder.where(status: ["pending", "partially_accepted"]).find_by(id: params[:id])
      return render json: { error: "Order request not found or already processed" }, status: :not_found unless order
      return render json: { error: "Order request expired" }, status: :unprocessable_entity if order.expires_at.present? && Time.current > order.expires_at
      return render json: { error: "Cannot accept your own request" }, status: :unprocessable_entity if order.buyer_dealer_id == current_dealer.id

      notification = Notification.find_by(receiver: current_dealer, notifiable: order, notification_type: "b2b_order_request")
      return render json: { error: "You are not allowed to accept this order" }, status: :forbidden unless notification

      ActiveRecord::Base.transaction do
        lock_order = B2bOrder.lock.includes(:buyer_dealer, b2b_order_items: [:product_variant, { dealer_product: :dealer }]).find(order.id)
        requested_ids = Array(params[:item_ids]).map(&:to_i).uniq
        candidate_items = requested_ids.present? ? lock_order.b2b_order_items.open_items.where(id: requested_ids) : lock_order.b2b_order_items.open_items

        updated_items = resolve_order_items_for_seller(candidate_items, current_dealer)
        raise StandardError, "You don't have enough stock for the selected items" if updated_items.blank?

        updated_items.each do |item, dealer_product, unit_price|
          item.update!(
            dealer_product_id: dealer_product.id,
            status: "accepted",
            responded_at: Time.current,
            unit_price: unit_price,
            total_price: unit_price * item.quantity.to_i
          )
        end

        lock_order.update!(seller_dealer_id: current_dealer.id) if lock_order.seller_dealer_id.blank?
        lock_order.recalculate_totals!
        lock_order.refresh_status!

        updated_items.each do |item, dealer_product, _unit_price|
          dealer_product.reload
          dealer_product.update!(stock_quantity: dealer_product.stock_quantity.to_i - item.quantity.to_i)
        end

        Notification.where(notifiable: lock_order, notification_type: "b2b_order_request").find_each do |entry|
          payload = entry.payload.stringify_keys
          pending_item_ids = lock_order.b2b_order_items.open_items.pluck(:id)
          visible_item_ids = Array(payload["item_ids"]).map(&:to_i)
          remaining_for_recipient = visible_item_ids & pending_item_ids

          entry.update!(
            payload: payload.merge(
              "b2b_state" => remaining_for_recipient.empty? ? "cancelled" : "open",
              "item_ids" => remaining_for_recipient,
              "items" => serialize_b2b_items(lock_order.b2b_order_items.where(id: remaining_for_recipient))
            ),
            read_at: (entry.receiver == current_dealer ? Time.current : entry.read_at)
          )
        end

        buyer = lock_order.buyer_dealer
        NotificationService.deliver(
          recipient: buyer,
          actor: current_dealer,
          notifiable: lock_order,
          kind: "b2b_order_accepted",
          title: "Dealer accepted your B2B request",
          message: "#{current_dealer.dealer_code} accepted #{updated_items.size} item(s) from your request.",
          visible_in_app: true,
          delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
          payload: {
            order_id: lock_order.id,
            seller_dealer_id: current_dealer.id,
            seller_name: current_dealer.dealer_code,
            accepted_item_ids: updated_items.map { |item, _dealer_product, _price| item.id },
            accepted_items: serialize_b2b_items(updated_items.map(&:first)),
            b2b_state: lock_order.status
          }
        )

        B2bOrderMailer.acceptance_update(lock_order.id, current_dealer.id, updated_items.map { |item, _dealer_product, _price| item.id }).deliver_later if buyer.email.present?
      end

      render json: { message: "B2B items accepted successfully" }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def require_dealer!
      return if current_dealer.present?

      render json: { error: "Dealer only" }, status: :unauthorized
    end

    def incoming_order_scope
      ids = Notification.where(
        receiver: current_dealer,
        notification_type: "b2b_order_request",
        notifiable_type: "B2bOrder"
      ).select do |notification|
        notification.payload.fetch("b2b_state", "open") == "open" && Array(notification.payload["item_ids"]).any?
      end.map(&:notifiable_id)

      B2bOrder.where(id: ids, status: ["pending", "partially_accepted"])
              .includes(:buyer_dealer, :seller_dealer, b2b_order_items: { dealer_product: :dealer })
              .order(created_at: :desc)
    end

    def eligible_nearby_dealers(order:)
      Dealer.active
            .includes(:dealer_location, dealer_products: [:product_variant, :product])
            .where.not(id: order.buyer_dealer_id)
            .each_with_object({}) do |dealer, matches|
        loc = dealer.dealer_location
        next unless loc&.is_active && loc.latitude.present? && loc.longitude.present?

        distance = DealerLocation.distance_km(order.latitude, order.longitude, loc.latitude, loc.longitude)
        next if distance > order.requested_radius_km.to_f
        next if loc.service_radius_km.present? && distance > loc.service_radius_km.to_f

        matched_items = order.b2b_order_items.open_items.select do |item|
          dealer.dealer_products.any? do |dp|
            dp.approved? && dp.is_active && dp.stock_quantity.to_i >= item.quantity.to_i && dp.product_variant_id == item.product_variant_id
          end
        end

        matches[dealer] = matched_items if matched_items.any?
      end
    end

    def resolve_order_items_for_seller(items_scope, dealer)
      resolved = []

      items_scope.each do |item|
        dealer_product = dealer.dealer_products.live.find_by(product_variant_id: item.product_variant_id)
        return nil if dealer_product.blank? || dealer_product.stock_quantity.to_i < item.quantity.to_i

        unit_price = dealer_product.product_variant.dealer_selling_price.to_d
        resolved << [item, dealer_product, unit_price]
      end

      resolved
    end

    def serialize_b2b_items(items)
      Array(items).map do |item|
        {
          id: item.id,
          product_variant_id: item.product_variant_id,
          product_name: item.product_variant&.product&.name,
          variant_sku: item.product_variant&.variant_sku,
          quantity: item.quantity,
          unit_price: item.unit_price.to_f,
          total_price: item.total_price.to_f,
          status: item.status
        }
      end
    end
  end
end
