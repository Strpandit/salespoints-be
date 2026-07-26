module Api
  class DealerOrdersController < ApplicationController
    before_action :require_dealer!

    def index
      tab = params[:tab].to_s.presence || "incoming"
      time_filter = params[:time_filter].to_s.presence || "all"
      
      orders = fetch_orders(tab)
      
      orders = apply_time_filter(orders, time_filter)
      
      if params[:status].present? && params[:status] != "all"
        orders = orders.select { |o| o[:status] == params[:status] }
      end
      
      if params[:search].present?
        query = params[:search].strip.downcase
        orders = orders.select do |o|
          o[:reference_number].to_s.downcase.include?(query) ||
          o[:buyer_name].to_s.downcase.include?(query) ||
          o[:seller_name].to_s.downcase.include?(query)
        end
      end
      
      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 20).to_i
      total_count = orders.length
      paginated = orders[(page - 1) * per_page, per_page] || []
      
      stats = {
        total: orders.length,
        by_status: orders.group_by { |o| o[:status] }.transform_values(&:count),
        by_type: orders.group_by { |o| o[:type] }.transform_values(&:count),
        by_payment: orders.group_by { |o| o[:payment_method] }.transform_values(&:count),
        total_amount: orders.sum { |o| o[:total_amount].to_f }
      }
      
      render json: {
        data: paginated,
        meta: {
          current_page: page,
          next_page: page * per_page < total_count ? page + 1 : nil,
          prev_page: page > 1 ? page - 1 : nil,
          total_pages: (total_count.to_f / per_page).ceil,
          total_count: total_count
        },
        stats: stats,
        message: "Orders fetched successfully"
      }, status: :ok
    end

    def show
      order_id = params[:id].to_i
      
      b2b_order = current_dealer.buyer_b2b_orders.find_by(id: order_id) ||
                  current_dealer.seller_b2b_orders.find_by(id: order_id)
      
      if b2b_order.present?
        return render json: {
          data: transform_b2b_order_detail(b2b_order),
          message: "B2B order fetched successfully"
        }, status: :ok
      end

      retail_order = current_dealer.sales_orders.find_by(id: order_id) ||
                current_dealer.orders.find_by(id: order_id)

      if retail_order.present?
        return render json: {
          data: transform_retail_order_detail(retail_order),
          message: "B2C order fetched successfully"
        }, status: :ok
      end
      
      render json: { error: "Order not found" }, status: :not_found
    end
    
    private

    def require_dealer!
      render json: { error: "Dealer only" }, status: :unauthorized unless current_dealer
    end

    def fetch_orders(tab)
      case tab
      when "incoming"
        fetch_incoming_orders
      when "accepted"
        fetch_accepted_orders
      when "outgoing"
        fetch_outgoing_orders
      when "sales"
        fetch_sales_orders
      when "purchases"
        fetch_purchase_orders
      else
        fetch_incoming_orders
      end
    end

    def fetch_incoming_orders
      results = []

      b2b_orders = current_dealer.b2b_order_offers
                                  .open_state
                                  .includes(b2b_order: [:buyer_dealer, :seller_dealer, :b2b_order_items])
                                  .map(&:b2b_order)
                                  .select { |o| o.pending_request? && o.parent_request_order_id.nil? }
      
      b2b_orders.each do |o|
        results << transform_b2b_order(o, "incoming")
      end

      b2c_orders = current_dealer.sales_orders
                                  .where(status: "pending")
                                  .includes(:buyer, :order_items)
      
      b2c_orders.each do |o|
        results << transform_retail_order(o, "incoming")
      end

      results.sort_by { |o| o[:created_at] }.reverse
    end

    def fetch_accepted_orders
      results = []

      b2b_orders = current_dealer.seller_b2b_orders
                                  .child_orders
                                  .where("request_status = ? OR (request_status IS NULL AND status IN (?))", 
                                        "accepted_request", 
                                        %w[pending_payment paid confirmed shipped delivered cancelled])
                                  .includes(:buyer_dealer, :seller_dealer, :b2b_order_items)
      
      b2b_orders.each do |o|
        results << transform_b2b_order(o, "accepted")
      end

      b2c_orders = current_dealer.sales_orders
                                  .where(status: %w[processing shipped delivered])
                                  .includes(:buyer, :order_items)
      
      b2c_orders.each do |o|
        results << transform_retail_order(o, "accepted")
      end

      results.sort_by { |o| o[:created_at] }.reverse
    end

    def fetch_outgoing_orders
      results = []

      b2b_orders = current_dealer.buyer_b2b_orders
                                  .final_orders
                                  .where("status IN (?)", %w[pending_request pending_payment paid confirmed shipped delivered cancelled])
                                  .includes(:buyer_dealer, :seller_dealer, :b2b_order_items)
      
      b2b_orders.each do |o|
        results << transform_b2b_order(o, "outgoing")
      end

      b2c_orders = current_dealer.orders
                                  .includes(:buyer, :order_items)
      
      b2c_orders.each do |o|
        results << transform_retail_order(o, "outgoing")
      end

      results.sort_by { |o| o[:created_at] }.reverse
    end

    def fetch_sales_orders
      results = []

      b2b_orders = current_dealer.seller_b2b_orders
                                  .includes(:buyer_dealer, :seller_dealer, :b2b_order_items)
      
      b2b_orders.each do |o|
        results << transform_b2b_order(o, "sales")
      end

      b2c_orders = current_dealer.sales_orders
                                  .includes(:buyer, :order_items)
      
      b2c_orders.each do |o|
        results << transform_retail_order(o, "sales")
      end

      results.sort_by { |o| o[:created_at] }.reverse
    end

    def fetch_purchase_orders
      results = []

      b2b_orders = current_dealer.buyer_b2b_orders
                                  .includes(:buyer_dealer, :seller_dealer, :b2b_order_items)
      
      b2b_orders.each do |o|
        results << transform_b2b_order(o, "purchases")
      end

      b2c_orders = current_dealer.orders
                                  .includes(:buyer, :order_items)
      
      b2c_orders.each do |o|
        results << transform_retail_order(o, "purchases")
      end

      results.sort_by { |o| o[:created_at] }.reverse
    end

    def transform_b2b_order(order, source_tab)
      meta = b2b_order_meta(order)
      
      {
        id: order.id,
        type: "b2b",
        tab: source_tab,
        reference_number: order.reference_number || order.id.to_s,
        status: order.status,
        request_status: order.request_status,
        display_status: meta[:label],
        status_color: meta[:color],
        status_bg: meta[:bg],
        status_note: meta[:note],
        total_amount: order.total_amount.to_f,
        subtotal_amount: order.subtotal_amount.to_f,
        tax_amount: order.tax_amount.to_f,
        payment_method: order.payment_method || "cod",
        payment_status: order.payment_status || "pending",
        buyer_name: order.buyer_dealer&.dealer_code || order.buyer_dealer&.full_name || "Dealer",
        buyer_id: order.buyer_dealer_id,
        seller_name: order.seller_dealer&.dealer_code || order.seller_dealer&.full_name || "Dealer",
        seller_id: order.seller_dealer_id,
        created_at: order.created_at.iso8601,
        requested_at: order.requested_at&.iso8601,
        accepted_at: order.accepted_at&.iso8601,
        confirmed_at: order.confirmed_at&.iso8601,
        shipped_at: order.shipped_at&.iso8601,
        delivered_at: order.delivered_at&.iso8601,
        expires_at: order.expires_at&.iso8601,
        requested_radius_km: order.requested_radius_km || 5,
        accepted_items_count: order.b2b_order_items.accepted_items.count,
        open_items_count: order.b2b_order_items.open_items.count,
        items: order.b2b_order_items.map { |item| transform_b2b_item(item) },
        delivery_confirmation: order.delivery_confirmation&.as_json(only: [:token, :status, :submitted_at, :completed_at]),
        can_accept: order.pending_request? && !order.expired?,
        can_reject: order.pending_request? && !order.expired?,
        can_update: order.can_transition_to?("shipped") || order.can_transition_to?("delivered")
      }
    end

    def transform_retail_order(order, source_tab)
      meta = retail_order_meta(order)
      
      buyer_name = if order.buyer_type == "Account"
        order.buyer&.full_name || order.buyer&.first_name || "Customer"
      elsif order.buyer_type == "Dealer"
        order.buyer&.dealer_code || order.buyer&.full_name || "Dealer"
      else
        "Customer"
      end

      {
        id: order.id,
        type: "retail",
        tab: source_tab,
        reference_number: order.order_number,
        status: order.status,
        display_status: meta[:label],
        status_color: meta[:color],
        status_bg: meta[:bg],
        total_amount: order.total_amount.to_f,
        subtotal_amount: order.subtotal_amount.to_f,
        tax_amount: order.tax_amount.to_f,
        payment_method: order.payment_method || "cod",
        payment_status: order.payment_status || "pending",
        buyer_name: buyer_name,
        buyer_id: order.buyer_id,
        buyer_type: order.buyer_type,
        seller_name: order.seller_dealer&.dealer_code || order.seller_dealer&.full_name || "Dealer",
        seller_id: order.seller_dealer_id,
        created_at: order.created_at.iso8601,
        placed_at: order.placed_at&.iso8601,
        shipped_at: order.shipped_at&.iso8601,
        delivered_at: order.delivered_at&.iso8601,
        settlement_status: order.settlement_status || "on_hold",
        seller_settlement_amount: order.seller_settlement_amount.to_f,
        refund_amount: order.refund_amount.to_f,
        refund_status: order.refund_status || "none",
        items: order.order_items.map { |item| transform_retail_item(item) },
        delivery_confirmation: order.delivery_confirmation&.as_json(only: [:token, :status, :submitted_at, :completed_at]),
        can_update: order.can_transition_to?("processing") || order.can_transition_to?("shipped"),
        next_status: order.status == "pending" ? "processing" : (order.status == "processing" ? "shipped" : nil)
      }
    end

    def transform_b2b_item(item)
      {
        id: item.id,
        product_name: item.product_variant&.product&.name || "Product",
        variant_sku: item.product_variant&.variant_sku || "N/A",
        quantity: item.quantity,
        unit_price: item.unit_price.to_f,
        total_price: item.total_price.to_f,
        status: item.status,
        accepted: item.accepted?
      }
    end

    def transform_retail_item(item)
      {
        id: item.id,
        product_name: item.product_name_with_variant || "Item",
        quantity: item.quantity,
        unit_price: item.unit_price.to_f,
        total_price: item.total_price.to_f
      }
    end

    def b2b_order_meta(order)
      if order.request_status == "pending_request"
        { label: "Request Sent", color: "#946200", bg: "#FFF7E6", note: "Waiting for seller response" }
      elsif order.status == "pending_payment"
        { label: "Payment Pending", color: "#0958D9", bg: "#E6F0FF", note: "Payment link sent" }
      elsif order.status == "paid"
        { label: "Paid", color: "#0A7B3E", bg: "#E7F8EE", note: "Payment confirmed" }
      elsif order.status == "confirmed"
        { label: "Confirmed", color: "#0A7B3E", bg: "#E7F8EE", note: "#{(order.payment_method || 'cod').upcase}" }
      elsif order.status == "shipped"
        { label: "Shipped", color: "#6B21A8", bg: "#F3E8FF", note: "In transit" }
      elsif order.status == "delivered"
        { label: "Delivered", color: "#0A7B3E", bg: "#E7F8EE", note: "Delivered" }
      elsif order.status == "cancelled"
        { label: "Closed", color: "#B42318", bg: "#FEECEB", note: order.request_status == "rejected_request" ? "Rejected by seller" : "Cancelled" }
      else
        { label: order.status || "Pending", color: "#54595E", bg: "#F1F3F4", note: "" }
      end
    end

    def retail_order_meta(order)
      status_meta = {
        "pending" => { label: "Pending", color: "#946200", bg: "#FFF7E6" },
        "processing" => { label: "Processing", color: "#0958D9", bg: "#E6F0FF" },
        "shipped" => { label: "Shipped", color: "#6B21A8", bg: "#F3E8FF" },
        "delivered" => { label: "Delivered", color: "#0A7B3E", bg: "#E7F8EE" },
        "cancelled" => { label: "Cancelled", color: "#B42318", bg: "#FEECEB" },
        "return_requested" => { label: "Return Requested", color: "#946200", bg: "#FFF7E6" },
        "return_approved" => { label: "Return Approved", color: "#0958D9", bg: "#E6F0FF" },
        "return_in_transit" => { label: "Return In Transit", color: "#6B21A8", bg: "#F3E8FF" },
        "returned" => { label: "Returned", color: "#B42318", bg: "#FEECEB" },
        "replacement_requested" => { label: "Replacement Requested", color: "#946200", bg: "#FFF7E6" },
        "replacement_approved" => { label: "Replacement Approved", color: "#0958D9", bg: "#E6F0FF" },
        "replacement_shipped" => { label: "Replacement Shipped", color: "#6B21A8", bg: "#F3E8FF" },
        "replacement_delivered" => { label: "Replacement Delivered", color: "#0A7B3E", bg: "#E7F8EE" }
      }
      status_meta[order.status] || { label: order.status || "Pending", color: "#54595E", bg: "#F1F3F4" }
    end

    def apply_time_filter(orders, filter)
      return orders if filter == "all" || filter.blank?
      
      case filter
      when "today"
        orders.select { |o| Time.parse(o[:created_at]).to_date == Date.current }
      when "this_week"
        orders.select { |o| Time.parse(o[:created_at]) >= Date.current.beginning_of_week }
      when "this_month"
        orders.select { |o| Time.parse(o[:created_at]) >= Date.current.beginning_of_month }
      when "custom"
        if params[:date_from].present? && params[:date_to].present?
          from = Date.parse(params[:date_from]).beginning_of_day
          to = Date.parse(params[:date_to]).end_of_day
          orders.select { |o| Time.parse(o[:created_at]).between?(from, to) }
        else
          orders
        end
      else
        orders
      end
    end
  end
end