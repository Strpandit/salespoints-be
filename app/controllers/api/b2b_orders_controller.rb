module Api
  class B2bOrdersController < ApplicationController
    before_action :require_dealer!, except: [:payment]
    skip_before_action :authenticate_request!, only: [:payment]

    def index
      view = params[:view].to_s
      time_filter = params[:time_filter].to_s.presence || "all"

      base_orders =
        case view
        when "incoming"
          current_dealer.b2b_order_offers
                  .open_state
                  .includes(b2b_order: [:buyer_dealer, :seller_dealer, :b2b_order_items])
                  .map(&:b2b_order)
                  .select { |o| o.pending_request? && o.request_status.present? }
                  .uniq
        when "accepted"
          current_dealer.seller_b2b_orders
                        .where.not(request_status: nil)
                        .where("request_status = ? OR (request_status IS NULL AND status IN (?))", "accepted_request", %w[pending_payment paid confirmed shipped delivered cancelled])
                        .includes(:buyer_dealer, :seller_dealer, b2b_order_items: { dealer_product: :dealer })
                        .order(created_at: :desc)
                        .distinct
        else
          current_dealer.buyer_b2b_orders
                  .where(request_status: nil)
                  .where("status IN (?)", %w[pending_request pending_payment paid confirmed shipped delivered cancelled])
                  .includes(:buyer_dealer, :seller_dealer, b2b_order_items: { dealer_product: :dealer })
                  .order(created_at: :desc)
                  .distinct
        end

      orders = apply_time_filter(base_orders, time_filter)

      if orders.is_a?(Array)
        paginated = Kaminari.paginate_array(orders).page(params[:page]).per(params[:per_page] || 20)
      else
        paginated = orders.page(params[:page]).per(params[:per_page] || 20)
      end
      
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

    def show
      order = current_dealer.buyer_b2b_orders.find_by(id: params[:id]) ||
              current_dealer.seller_b2b_orders.find_by(id: params[:id])
      
      return render json: { error: "Order not found" }, status: :not_found unless order
      
      render json: serialize_resource(order, B2bOrderSerializer, include: [:b2b_order_items, :delivery_confirmation], base_url: request.base_url).merge(
        message: "B2B order fetched successfully"
      ), status: :ok
    end

    def place_direct
      pincode = params[:pincode].presence

      return render json: { error: "Product is required" }, status: :unprocessable_entity if params[:product_id].blank?
      return render json: { error: "Variant is required" }, status: :unprocessable_entity if params[:product_variant_id].blank?
      return render json: { error: "Pincode is required" }, status: :unprocessable_entity if params[:pincode].blank?

      use_business_address = params[:use_business_address].to_s == "true"
      delivery_address = nil

      if !use_business_address && params[:delivery_address].present?
        delivery_address = Address.new(
          address_line1: params[:delivery_address][:address_line1],
          address_line2: params[:delivery_address][:address_line2],
          city: params[:delivery_address][:city],
          state: params[:delivery_address][:state],
          country: params[:delivery_address][:country] || "India",
          postal_code: params[:delivery_address][:postal_code] || pincode,
          phone: params[:delivery_address][:phone],
          name: params[:delivery_address][:name],
          latitude: params[:delivery_address][:latitude],
          longitude: params[:delivery_address][:longitude],
          dealer_id: current_dealer.id
        )
        
        delivery_address.save!
      end

      payment_method = nil
      payment_status = nil
      quantity = params[:quantity].to_i
      quantity = 1 if quantity <= 0

      order = B2bDirectOrderService.new(
        buyer: current_dealer,
        product_id: params[:product_id],
        product_variant_id: params[:product_variant_id],
        product_variant_color_id: params[:product_variant_color_id],
        quantity: quantity,
        payment_method: payment_method,
        payment_status: payment_status,
        pincode: pincode,
        delivery_address: delivery_address,
        use_business_address: use_business_address
      ).call

      render json: serialize_resource(order, B2bOrderSerializer, base_url: request.base_url).merge(
        message: "Request sent to nearby dealers"
      ), status: :created
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def accept
      order = find_order(params[:id])
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
      order = find_order(params[:id])
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

    def download_invoice
      return render json: { error: "Unauthorized" }, status: :unauthorized unless current_dealer.present? || current_admin.present?

      order =
        if current_admin
          B2bOrder.find_by(id: params[:id]) || Order.find_by(id: params[:id])
        else
          current_dealer.buyer_b2b_orders.find_by(id: params[:id]) ||
          current_dealer.seller_b2b_orders.find_by(id: params[:id]) ||
          current_dealer.sales_orders.find_by(id: params[:id]) ||
          current_dealer.orders.find_by(id: params[:id])
        end

      return render json: { error: "Order not found" }, status: :not_found unless order
      unless %w[delivered replacement_requested replacement_approved replacement_shipped replacement_delivered].include?(order.status)
        return render json: { error: "Invoice can only be generated for delivered orders" }, status: :unprocessable_entity
      end
          
        generator = InvoicePdf.new(order)
        pdf = generator.generate

        send_data pdf,
          filename: "Invoice_#{order.reload.invoice_number}.pdf",
          type: "application/pdf",
          disposition: "attachment",
          status: :ok
        return
        
    rescue StandardError => e
      render json: { error: "Failed to generate invoice" }, status: :internal_server_error
    end

    def payment
      order =
        if params[:payment_token].present?
          B2bOrder.find_by(payment_token: params[:payment_token])
        else
          current_dealer&.buyer_b2b_orders&.find_by(id: params[:id])
        end
      return render json: { error: "Order not found" }, status: :not_found unless order
      return render json: { error: "Payment link expired" }, status: :unprocessable_entity if order.expires_at.present? && order.expires_at <= Time.current
      return render json: { error: "Payment already completed" }, status: :unprocessable_entity if order.payment_status == "paid"
      return render json: { error: "Order cancelled" }, status: :unprocessable_entity if order.status == "cancelled"
      return render json: { error: "Order rejected" }, status: :unprocessable_entity if order.request_status == "rejected_request"

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
      raise
    end

    def update_status
      order = find_seller_order(params[:id])
      order = current_dealer.seller_b2b_orders.includes(:delivery_confirmation).find_by(id: params[:id])
      return render json: { error: "Order not found" }, status: :not_found unless order

      next_status = params[:status].to_s
      return render json: { error: "Status is required" }, status: :unprocessable_entity if next_status.blank?
      return render json: { error: "Delivered status will be set automatically after delivery proof verification" }, status: :unprocessable_entity if next_status == "delivered"
      return render json: { error: "Invalid status transition" }, status: :unprocessable_entity unless order.can_transition_to?(next_status)

      case next_status
      when "shipped"
        if order.is_a?(B2bOrder)
          order.mark_shipped!(note: "params[:status_note]")
          EmailDispatcherService.b2b_order_shipped(order)
        elsif order.is_a?(Order)
          order.update!(
            status: "shipped",
            shipped_at: Time.current,
            status_note: params[:status_note] || "Marked as shipped"
          )
          EmailDispatcherService.retail_order_shipped(order)
        end

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

    def apply_time_filter(orders, filter)
      return orders if filter.blank? || filter == "all"

      unless orders.is_a?(ActiveRecord::Relation)
        return case filter
              when "today"
                orders.select { |o| o.created_at.to_date == Date.current }
              when "this_week"
                orders.select { |o| o.created_at >= Date.current.beginning_of_week }
              when "this_month"
                orders.select { |o| o.created_at >= Date.current.beginning_of_month }
              when "custom"
                begin
                  return orders unless params[:date_from].present? && params[:date_to].present?

                  from = Date.parse(params[:date_from]).beginning_of_day
                  to   = Date.parse(params[:date_to]).end_of_day

                  orders.select { |o| o.created_at.between?(from, to) }
                rescue ArgumentError
                  orders
                end
              else
                orders
              end
      end
      
      case filter
      when "today"
        orders.where(created_at: Date.current.all_day)
      when "this_week"
        orders.where(created_at: Date.current.beginning_of_week..Time.current)
      when "this_month"
        orders.where(created_at: Date.current.beginning_of_month..Time.current)
      when "custom"
        return orders unless params[:date_from].present? && params[:date_to].present?

        begin
          from = Date.parse(params[:date_from]).beginning_of_day
          to   = Date.parse(params[:date_to]).end_of_day

          orders.where(created_at: from..to)
        rescue ArgumentError
          orders
        end

      else
        orders
      end
    end

    def find_order(id)
      b2b_order = current_dealer.seller_b2b_orders.find_by(id: id) ||
                  B2bOrder.joins(:b2b_order_offers)
                          .where(b2b_order_offers: { dealer_id: current_dealer.id, status: "open" })
                          .find_by(id: id)
      return b2b_order if b2b_order.present?

      retail_order = current_dealer.sales_orders.find_by(id: id) ||
                     Order.joins(:order_offers)
                          .where(order_offers: { dealer_id: current_dealer.id, status: "open" })
                          .find_by(id: id)
      return retail_order if retail_order.present?
      
      nil
    end

    def find_seller_order(id)
      current_dealer.seller_b2b_orders.find_by(id: id) ||
      current_dealer.seller_orders.find_by(id: id)
    end

    def acceptable_order?(order)
      return false if order.nil?
      
      if order.is_a?(B2bOrder)
        return false unless order.request_status == "pending_request"
        return false unless order.status.in?(%w[pending_request pending_payment])
        return false if order.seller_dealer_id.present? && order.seller_dealer_id != current_dealer.id
        return false if order.expires_at.present? && Time.current > order.expires_at
        true
      elsif order.is_a?(Order)
        return false unless order.status == "pending"
        return false if order.seller_dealer_id.present? && order.seller_dealer_id != current_dealer.id
        return false if order.expires_at.present? && Time.current > order.expires_at
        true
      else
        false
      end
    end

    def matching_open_offer(order:)
      if order.is_a?(B2bOrder)
        order.b2b_order_offers.where(dealer: current_dealer, status: "open").order(created_at: :desc).first
      elsif order.is_a?(Order)
        order.order_offers.where(dealer: current_dealer, status: "open").order(created_at: :desc).first
      end 
    end
  end
end
