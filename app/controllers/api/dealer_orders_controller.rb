module Api
  class DealerOrdersController < ApplicationController
    before_action :require_dealer!

    def index
      tab = params[:tab].to_s.presence || "incoming"
      time_filter = params[:time_filter].to_s.presence || "all"
      
      orders = fetch_orders(tab)
      orders = apply_time_filter(orders, time_filter)
      
      # Compute stats on the full tab dataset before status filtering
      stats = {
        total: orders.length,
        by_status: orders.group_by { |o| o[:status] }.transform_values(&:count),
        by_type: orders.group_by { |o| o[:type] }.transform_values(&:count),
        by_payment: orders.group_by { |o| o[:payment_method] }.transform_values(&:count),
        by_source: orders.group_by { |o| o[:source_type] }.transform_values(&:count),
        total_amount: orders.sum { |o| o[:total_amount].to_f }
      }

      if params[:status].present? && params[:status] != "all"
        b2b_request_statuses = %w[pending_request rejected_request accepted_request]
        if b2b_request_statuses.include?(params[:status])
          orders = orders.select { |o| o[:request_status] == params[:status] }
        else
          orders = orders.select { |o| o[:status] == params[:status] }
        end
      end
      
      if params[:source_type].present? && params[:source_type] != "all"
        if params[:source_type] == "b2c"
          orders = orders.select { |o| o[:type] == "retail" || o[:source_type] == "retail" }
        elsif params[:source_type] == "b2b"
          orders = orders.select { |o| o[:source_type] == "b2b" || o[:source_type] == "direct_buy" }
        elsif params[:source_type] == "wholesale"
          orders = orders.select { |o| o[:source_type] == "wholesale" }
        else
          orders = orders.select { |o| o[:source_type] == params[:source_type] }
        end
      end

      if params[:payment_method].present? && params[:payment_method] != "all"
        if params[:payment_method] == "online"
          orders = orders.select { |o| %w[online upi card netbanking].include?(o[:payment_method].to_s.downcase) || (o[:payment_method].to_s.downcase != "cod" && o[:payment_method].to_s.downcase != "cash" && o[:payment_method].to_s.downcase != "pay_on_delivery") }
        elsif params[:payment_method] == "cod"
          orders = orders.select { |o| %w[cod cash pay_on_delivery].include?(o[:payment_method].to_s.downcase) || o[:payment_method].blank? }
        else
          orders = orders.select { |o| o[:payment_method].to_s.downcase == params[:payment_method].to_s.downcase }
        end
      end

      if params[:issues_filter].present? && params[:issues_filter] != "all"
        case params[:issues_filter]
        when "replacement_request"
          orders = orders.select { |o| o[:replacement_request].present? }
        when "return_request"
          orders = orders.select { |o| o[:return_requests].present? && o[:return_requests].any? }
        when "delivery_pending"
          orders = orders.select { |o| o[:delivery_confirmation].present? }
        end
      end

      if params[:min_amount].present?
        min_val = params[:min_amount].to_f
        orders = orders.select { |o| o[:total_amount].to_f >= min_val }
      end

      if params[:max_amount].present?
        max_val = params[:max_amount].to_f
        orders = orders.select { |o| o[:total_amount].to_f <= max_val }
      end
      
      if params[:search].present?
        query = params[:search].strip.downcase
        orders = orders.select do |o|
          o[:reference_number].to_s.downcase.include?(query) ||
          o[:buyer_name].to_s.downcase.include?(query) ||
          o[:seller_name].to_s.downcase.include?(query) ||
          (o[:items] || []).any? { |item| (item[:title] || item[:product_name] || "").to_s.downcase.include?(query) || (item[:sku] || "").to_s.downcase.include?(query) }
        end
      end

      case params[:sort_by]
      when "oldest"
        orders = orders.sort_by { |o| o[:created_at] }
      when "amount_desc"
        orders = orders.sort_by { |o| o[:total_amount] }.reverse
      when "amount_asc"
        orders = orders.sort_by { |o| o[:total_amount] }
      else
        orders = orders.sort_by { |o| o[:created_at] }.reverse
      end
      
      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 20).to_i
      total_count = orders.length
      paginated = orders[(page - 1) * per_page, per_page] || []
      
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
                  current_dealer.seller_b2b_orders.find_by(id: order_id) ||
                  B2bOrder.joins(:b2b_order_offers).where(b2b_order_offers: { dealer_id: current_dealer.id }).find_by(id: order_id)

      if b2b_order.present?
        source_tab = if b2b_order.buyer_dealer_id == current_dealer.id
                       "outgoing"
                     elsif b2b_order.seller_dealer_id == current_dealer.id
                       "accepted"
                     else
                       "incoming"
                     end
        return render json: {
          data: transform_b2b_order_detail(b2b_order, source_tab),
          message: "B2B order fetched successfully"
        }, status: :ok
      end

      retail_order = current_dealer.sales_orders.find_by(id: order_id) ||
                     current_dealer.orders.find_by(id: order_id) ||
                     Order.joins(:order_offers).where(order_offers: { dealer_id: current_dealer.id }).find_by(id: order_id)

      if retail_order.present?
        source_tab = retail_order.seller_dealer_id == current_dealer.id ? (retail_order.status == "pending" ? "incoming" : "accepted") : "outgoing"
        return render json: {
          data: transform_retail_order_detail(retail_order, source_tab),
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
                                  .uniq
                                  .select(&:pending_request?)
      
      b2b_orders.each do |o|
        results << transform_b2b_order(o, "incoming")
      end

      b2c_offers_orders = current_dealer.order_offers
                                         .open_state
                                         .includes(order: [:buyer, :order_items])
                                         .map(&:order)
                                         .compact
                                         .uniq
                                         .select { |o| o.status == "pending" }

      direct_b2c_orders = current_dealer.sales_orders
                                         .where(status: "pending")
                                         .includes(:buyer, :order_items)

      b2c_orders = (b2c_offers_orders + direct_b2c_orders).uniq
      
      b2c_orders.each do |o|
        results << transform_retail_order(o, "incoming")
      end

      results.sort_by { |o| o[:created_at] }.reverse
    end

    def fetch_accepted_orders
      results = []

      b2b_orders = current_dealer.seller_b2b_orders
                                  .where(
                                    "request_status = ? OR (request_status IS NULL AND status IN (?))", 
                                    "accepted_request", 
                                    %w[pending_payment paid confirmed processing shipped delivered return_requested return_approved return_in_transit returned replacement_requested replacement_approved replacement_shipped replacement_delivered cancelled]
                                  )
                                  .includes(:buyer_dealer, :seller_dealer, :b2b_order_items)
      
      b2b_orders.each do |o|
        results << transform_b2b_order(o, "accepted")
      end

      b2c_orders = current_dealer.sales_orders
                                  .where(status: %w[confirmed processing shipped delivered return_requested return_approved return_in_transit returned replacement_requested replacement_approved replacement_shipped replacement_delivered cancelled])
                                  .includes(:buyer, :order_items)
      
      b2c_orders.each do |o|
        results << transform_retail_order(o, "accepted")
      end

      results.sort_by { |o| o[:created_at] }.reverse
    end

    def fetch_outgoing_orders
      results = []

      b2b_orders = current_dealer.buyer_b2b_orders
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

    def transform_b2b_order(order, source_tab)
      meta = b2b_order_meta(order)

      replacement_request = order.return_requests
                           .where(request_type: "replacement")
                           .order(created_at: :desc)
                           .first
      
      is_buyer = order.buyer_dealer_id == current_dealer.id
      is_seller = order.seller_dealer_id == current_dealer.id
      
      source_type = if order.is_direct_buy? && order.source_type == "WholesalerPost"
        "wholesale"
      elsif order.is_direct_buy?
        "direct_buy"
      else
        "b2b"
      end
      
      {
        id: order.id,
        type: "b2b",
        tab: source_tab,
        source_type: source_type,
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
        billing_address: order.billing_address,
        shipping_address: order.shipping_address,
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
        delivery_confirmation: is_seller && order.delivery_confirmation ? delivery_confirmation_payload(order.delivery_confirmation) : nil,
        replacement_delivery_confirmation: is_seller && order.replacement_delivery_confirmation ? delivery_confirmation_payload(order.replacement_delivery_confirmation) : nil,
        can_accept: !is_buyer && order.pending_request? && !order.expired? && (order.seller_dealer_id.nil? || order.seller_dealer_id == current_dealer.id || order.b2b_order_offers.where(dealer_id: current_dealer.id).exists?),
        can_reject: !is_buyer && order.pending_request? && !order.expired? && (order.seller_dealer_id.nil? || order.seller_dealer_id == current_dealer.id || order.b2b_order_offers.where(dealer_id: current_dealer.id).exists?),
        can_update: order.can_transition_to?("shipped") && order.seller_dealer_id == current_dealer.id,
        can_download_invoice: order.buyer_dealer_id == current_dealer.id,
        replacement_request: replacement_request.present? ? ReturnRequestSerializer.new(replacement_request, base_url: request.base_url).serializable_hash : nil,
        can_request_replacement: is_buyer && order.replacement_allowed?,
        can_manage_replacement: is_seller && replacement_request.present? && replacement_request&.open?,
        next_status: b2b_next_status(order)
      }
    end

    def transform_retail_order(order, source_tab)
      meta = retail_order_meta(order)

      replacement_request = order.return_requests
                           .where(request_type: "replacement")
                           .order(created_at: :desc)
                           .first

      is_buyer = order.buyer_id == current_dealer.id
      is_seller = order.seller_dealer_id == current_dealer.id
      
      buyer_name = if order.buyer_type == "Account"
        order.buyer&.full_name || order.buyer&.first_name || "Customer"
      elsif order.buyer_type == "Dealer"
        order.buyer&.dealer_code || order.buyer&.full_name || "Dealer"
      else
        "Customer"
      end

        has_open_offer = current_dealer.order_offers.where(order_id: order.id, status: "open").exists?

        {
          id: order.id,
          type: "retail",
          tab: source_tab,
          source_type: "retail",
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
          billing_address: order.billing_address,
          shipping_address: order.shipping_address,
          created_at: order.created_at.iso8601,
          placed_at: order.placed_at&.iso8601,
          processing_at: order.processing_at&.iso8601,
          shipped_at: order.shipped_at&.iso8601,
          delivered_at: order.delivered_at&.iso8601,
          cancelled_at: order.cancelled_at&.iso8601,
          settlement_status: order.settlement_status || "on_hold",
          seller_settlement_amount: order.seller_settlement_amount.to_f,
          refund_amount: order.refund_amount.to_f,
          refund_status: order.refund_status || "none",
          items: order.order_items.map { |item| transform_retail_item(item) },
          delivery_confirmation: is_seller && order.delivery_confirmation ? delivery_confirmation_payload(order.delivery_confirmation) : nil,
          replacement_delivery_confirmation: is_seller && order.replacement_delivery_confirmation ? delivery_confirmation_payload(order.replacement_delivery_confirmation) : nil,
          replacement_request: replacement_request.present? ? ReturnRequestSerializer.new(replacement_request, base_url: request.base_url).serializable_hash : nil,
          can_accept: !is_buyer && order.status == "pending" && (is_seller || order.seller_dealer_id.nil? || has_open_offer),
          can_reject: !is_buyer && order.status == "pending" && (is_seller || order.seller_dealer_id.nil? || has_open_offer),
          can_request_replacement: is_buyer && order.replacement_allowed?,
          can_manage_replacement: is_seller && replacement_request.present? && replacement_request.open?,
          can_update: (order.can_transition_to?("processing") || order.can_transition_to?("shipped")) && order.seller_dealer_id == current_dealer.id,
          next_status: order.status == "pending" ? "processing" : (order.status == "processing" ? "shipped" : nil)
        }
    end

    def transform_b2b_item(item)
      item_product_name = item.product_variant&.product&.name || item.wholesaler_post&.title || "Product"
      item_variant_sku = item.product_variant&.variant_sku || item.wholesaler_post&.modal_no || "N/A"
      color = item.try(:ad_hoc_color).presence || item.try(:product_variant_color)&.color_name.presence || "Standard"

      {
        id: item.id,
        product_name: item_product_name,
        variant_sku: item_variant_sku,
        color: color,
        quantity: item.quantity,
        unit_price: item.unit_price.to_f,
        total_price: item.total_price.to_f,
        status: item.status,
        accepted: item.accepted?,
        image_url: b2b_item_image_url(item)
      }
    end

    def transform_retail_item(item)
      color = item.try(:ad_hoc_color).presence || item.try(:product_variant_color)&.color_name.presence || "Standard"

      {
        id: item.id,
        product_name: item.product_name_with_variant || item.product_name || "Item",
        variant_sku: item.try(:product_variant)&.variant_sku || "N/A",
        color: color,
        quantity: item.quantity,
        unit_price: item.unit_price.to_f,
        total_price: item.total_price.to_f,
        image_url: order_item_image_url(item)
      }
    end

    def order_item_image_url(item)
      pv = item.try(:product_variant)
      dp = item.try(:dealer_product)
      blob = pv&.media&.first&.blob || pv&.product&.media&.first&.blob || dp&.media&.first&.blob || dp&.product_variant&.media&.first&.blob || dp&.product&.media&.first&.blob
      return nil unless blob
      Rails.application.routes.url_helpers.rails_blob_url(blob, host: request.base_url)
    rescue StandardError
      nil
    end

    def b2b_item_image_url(item)
      blob = if item.try(:wholesaler_post_id).present?
               item.wholesaler_post&.media&.first&.blob
             elsif item.try(:dealer_product_id).present?
               dp = item.dealer_product
               dp&.media&.first&.blob || dp&.product_variant&.media&.first&.blob || dp&.product&.media&.first&.blob
             elsif item.try(:product_variant_id).present?
               pv = item.product_variant
               pv&.media&.first&.blob || pv&.product&.media&.first&.blob
             end
      return nil unless blob
      Rails.application.routes.url_helpers.rails_blob_url(blob, host: request.base_url)
    rescue StandardError
      nil
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
      elsif order.status == "replacement_requested"
        { label: "Replacement Requested", color: "#946200", bg: "#FFF7E6", note: "Awaiting seller response" }
      elsif order.status == "replacement_approved"
        { label: "Replacement Approved", color: "#0958D9", bg: "#E6F0FF", note: "Awaiting shipment" }
      elsif order.status == "replacement_shipped"
        { label: "Replacement Shipped", color: "#6B21A8", bg: "#F3E8FF", note: "Replacement in transit" }
      elsif order.status == "replacement_delivered"
        { label: "Replacement Delivered", color: "#0A7B3E", bg: "#E7F8EE", note: "OTP verification pending" }
      elsif order.status == "cancelled"
        { label: "Closed", color: "#B42318", bg: "#FEECEB", note: order.request_status == "rejected_request" ? "Rejected by seller" : "Cancelled" }
      else
        { label: order.status || "Pending", color: "#54595E", bg: "#F1F3F4", note: "" }
      end
    end

    def retail_order_meta(order)
      status_meta = {
        "pending" => { label: "Pending Request", color: "#946200", bg: "#FFF7E6" },
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

    def transform_b2b_order_detail(order, source_tab = "detail")
      base = transform_b2b_order(order, source_tab)
      
      base.merge({
        billing_address: order.billing_address,
        shipping_address: order.shipping_address,
        offers: order.b2b_order_offers.map do |offer|
          {
            dealer_id: offer.dealer_id,
            dealer_name: offer.dealer&.dealer_code,
            status: offer.status,
            responded_at: offer.responded_at&.iso8601
          }
        end,
        broadcast_trackers: order.dealer_broadcast_trackers.map do |tracker|
          {
            dealer_id: tracker.dealer_id,
            dealer_name: tracker.dealer&.dealer_code,
            radius_km: tracker.broadcast_radius_km,
            status: tracker.status
          }
        end
      })
    end

    def transform_retail_order_detail(order, source_tab = "detail")
      base = transform_retail_order(order, source_tab)
      
      base.merge({
        billing_address: order.billing_address,
        shipping_address: order.shipping_address,
        offers: order.order_offers.map do |offer|
          {
            dealer_id: offer.dealer_id,
            dealer_name: offer.dealer&.dealer_code,
            status: offer.status,
            responded_at: offer.responded_at&.iso8601
          }
        end,
        return_requests: order.return_requests.map do |rr|
          {
            id: rr.id,
            request_type: rr.request_type,
            status: rr.status,
            reason: rr.reason,
            refund_amount: rr.refund_amount.to_f
          }
        end
      })
    end

    def b2b_next_status(order)
      return "shipped" if order.can_transition_to?("shipped")

      nil
    end

    def apply_time_filter(orders, filter)
      return orders if filter == "all" || filter.blank?
      
      case filter
      when "today"
        orders.select { |o| Time.parse(o[:created_at]).to_date == Date.current }
      when "yesterday"
        orders.select { |o| Time.parse(o[:created_at]).to_date == Date.yesterday }
      when "7_days"
        orders.select { |o| Time.parse(o[:created_at]) >= 7.days.ago }
      when "30_days"
        orders.select { |o| Time.parse(o[:created_at]) >= 30.days.ago }
      when "this_week"
        orders.select { |o| Time.parse(o[:created_at]) >= Date.current.beginning_of_week }
      when "this_month"
        orders.select { |o| Time.parse(o[:created_at]) >= Date.current.beginning_of_month }
      when "custom"
        if params[:date_from].present? && params[:date_to].present?
          from = Date.parse(params[:date_from]).beginning_of_day rescue nil
          to = Date.parse(params[:date_to]).end_of_day rescue nil
          if from && to
            orders.select { |o| Time.parse(o[:created_at]).between?(from, to) }
          else
            orders
          end
        else
          orders
        end
      else
        orders
      end
    end

    def delivery_confirmation_payload(dc)
      return nil unless dc.present?

      {
        id: dc.id,
        token: dc.token,
        context: dc.context,
        status: dc.status,
        notes: dc.notes,
        buyer_name: dc.buyer_name,
        seller_name: dc.seller_name,
        buyer_phone: dc.buyer_phone,
        seller_phone: dc.seller_phone,
        buyer_otp_verified: dc.buyer_verified?,
        submitted_at: dc.submitted_at&.iso8601,
        completed_at: dc.completed_at&.iso8601,
        declarations: dc.declarations,
        uploads: {
          product_with_customer_image: attachment_payload(dc.product_with_customer_image),
          product_packaging_image: attachment_payload(dc.product_packaging_image),
          product_open_box_images: (dc.product_open_box_images || []).map { |file| attachment_payload(file) }.compact
        }
      }
    end

    def attachment_payload(file)
      return nil if file.blank?

      if file.respond_to?(:attached?)
        return nil unless file.attached?
        file = file.attachment
      end

      blob = file.respond_to?(:blob) ? file.blob : file
      return nil if blob.blank? || !blob.respond_to?(:filename)

      {
        filename: blob.filename.to_s,
        content_type: blob.content_type,
        byte_size: blob.byte_size,
        url: Rails.application.routes.url_helpers.rails_blob_url(blob, only_path: false)
      }
    rescue StandardError
      nil
    end
  end
end