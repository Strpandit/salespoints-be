module Api
  module Admin
    class OrdersController < ApplicationController
      before_action :require_admin!

      def index
        # Start with base queries
        retail_orders = Order.includes(:buyer, :seller_dealer, order_items: { product_variant: :product })
        b2b_orders = B2bOrder.includes(:buyer_dealer, :seller_dealer, b2b_order_items: { product_variant: :product })

        # ===== ORDER TYPE FILTER =====
        if params[:order_type].present?
          if params[:order_type] == "retail"
            b2b_orders = B2bOrder.none
          elsif params[:order_type] == "b2b"
            retail_orders = Order.none
          end
        end

        # ===== STATUS FILTER =====
        if params[:status].present? && params[:status] != "all"
          retail_orders = retail_orders.where(status: params[:status])
          b2b_orders = b2b_orders.where(status: params[:status])
        end

        # ===== B2B REQUEST STATUS FILTER =====
        if params[:request_status].present? && params[:request_status] != "all"
          b2b_orders = b2b_orders.where(request_status: params[:request_status])
        end

        # ===== SOURCE FILTER (B2B only) =====
        if params[:source_type].present? && params[:source_type] != "all"
          b2b_orders = b2b_orders.where(source_type: params[:source_type])
        end

        # ===== B2B DIRECT BUY FILTER =====
        if params[:is_direct_buy].present?
          is_direct = ActiveModel::Type::Boolean.new.cast(params[:is_direct_buy])
          b2b_orders = b2b_orders.where(is_direct_buy: is_direct)
        end

        # ===== DATE FILTER =====
        if params[:date_from].present?
          from = Date.parse(params[:date_from]).beginning_of_day
          retail_orders = retail_orders.where("orders.created_at >= ?", from)
          b2b_orders = b2b_orders.where("b2b_orders.created_at >= ?", from)
        end

        if params[:date_to].present?
          to = Date.parse(params[:date_to]).end_of_day
          retail_orders = retail_orders.where("orders.created_at <= ?", to)
          b2b_orders = b2b_orders.where("b2b_orders.created_at <= ?", to)
        end

        # ===== SEARCH =====
        if params[:search].present?
          query = "%#{params[:search].strip}%"
          
          # Retail search
          retail_orders = retail_orders
            .joins("LEFT JOIN accounts ON orders.buyer_id = accounts.id AND orders.buyer_type = 'Account'")
            .joins("LEFT JOIN dealers AS buyer_dealers ON orders.buyer_id = buyer_dealers.id AND orders.buyer_type = 'Dealer'")
            .where(
              "orders.order_number ILIKE :q OR accounts.email ILIKE :q OR accounts.first_name ILIKE :q OR accounts.phone ILIKE :q OR buyer_dealers.email ILIKE :q OR buyer_dealers.first_name ILIKE :q OR buyer_dealers.dealer_code ILIKE :q OR buyer_dealers.phone ILIKE :q",
              q: query
            )
          
          # B2B search
          b2b_orders = b2b_orders
            .joins("LEFT JOIN dealers AS buyers ON b2b_orders.buyer_dealer_id = buyers.id")
            .joins("LEFT JOIN dealers AS sellers ON b2b_orders.seller_dealer_id = sellers.id")
            .where(
              "b2b_orders.reference_number ILIKE :q OR buyers.email ILIKE :q OR buyers.first_name ILIKE :q OR buyers.dealer_code ILIKE :q OR buyers.phone ILIKE :q OR sellers.dealer_code ILIKE :q",
              q: query
            )
        end

        # ===== COMBINE AND TRANSFORM =====
        all_orders = []

        retail_orders.each do |order|
          all_orders << transform_retail_order(order)
        end

        b2b_orders.each do |order|
          all_orders << transform_b2b_order(order)
        end

        # Sort by created_at (newest first)
        all_orders = all_orders.sort_by { |o| o[:created_at] }.reverse

        # ===== PAGINATION =====
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 20).to_i
        total_count = all_orders.length
        
        paginated = all_orders[(page - 1) * per_page, per_page] || []

        render json: {
          data: paginated,
          meta: {
            current_page: page,
            next_page: page * per_page < total_count ? page + 1 : nil,
            prev_page: page > 1 ? page - 1 : nil,
            total_pages: (total_count.to_f / per_page).ceil,
            total_count: total_count
          },
          message: "Orders fetched successfully"
        }, status: :ok
      end

      def show
        order = Order.includes(:buyer, :seller_dealer, order_items: { product_variant: :product })
                     .find_by(id: params[:id])
        
        if order.present?
          return render json: {
            data: transform_retail_order(order)
          }, status: :ok
        end

        # Try B2B
        b2b_order = B2bOrder.includes(:buyer_dealer, :seller_dealer, b2b_order_items: { product_variant: :product })
                             .find_by(id: params[:id])
        
        if b2b_order.present?
          return render json: {
            data: transform_b2b_order(b2b_order)
          }, status: :ok
        end

        render json: { error: "Order not found" }, status: :not_found
      end

      def download_invoice
        order = Order.includes(:buyer, :seller_dealer, order_items: { product_variant: :product })
                .find_by(id: params[:id])

        if order.present?
          pdf = ::InvoicePdf.new(order).generate

          send_data pdf,
            filename: "Invoice_#{order.order_number}.pdf",
            type: "application/pdf",
            disposition: "attachment",
            status: :ok
          return
        end

        b2b_order = B2bOrder.includes(:buyer_dealer, :seller_dealer, b2b_order_items: { product_variant: :product }).find_by(id: params[:id])

        if b2b_order.present?
            pdf = ::InvoicePdf.new(b2b_order).generate

            send_data pdf,
              filename: "Invoice_#{b2b_order.reference_number}.pdf",
              type: "application/pdf",
              disposition: "attachment",
              status: :ok
            return
        end

        render json: { error: "Order not found" }, status: :not_found
      end

      private

      def transform_retail_order(order)
        {
          id: order.id,
          order_type: "retail",
          order_number: order.order_number,
          status: order.status,
          total_amount: order.total_amount.to_f,
          created_at: order.created_at.iso8601,
          items_count: order.order_items.sum(:quantity),
          
          # Customer Info
          customer_name: order.buyer&.full_name || order.buyer&.first_name || "Customer",
          customer_email: order.buyer&.email,
          buyer_type: order.buyer_type,
          buyer_id: order.buyer_id,
          
          # Seller Info
          seller_dealer_id: order.seller_dealer_id,
          seller_name: order.seller_dealer&.full_name || order.seller_dealer&.dealer_code,
          seller_dealer_code: order.seller_dealer&.dealer_code,
          
          # Payment
          payment_method: order.payment_method,
          payment_status: order.payment_status,
          payment_reference: order.payment_reference,
          
          # Settlement
          settlement_status: order.settlement_status,
          seller_settlement_amount: order.seller_settlement_amount.to_f,
          refund_amount: order.refund_amount.to_f,
          refund_status: order.refund_status,
          
          # Addresses
          billing_address: order.billing_address,
          shipping_address: order.shipping_address,
          
          # Timestamps
          placed_at: order.placed_at&.iso8601,
          shipped_at: order.shipped_at&.iso8601,
          delivered_at: order.delivered_at&.iso8601,
          cancelled_at: order.cancelled_at&.iso8601,
          
          # Items
          order_items: order.order_items.map do |item|
            {
              id: item.id,
              product_name: item.product_name,
              product_name_with_variant: item.product_name_with_variant,
              quantity: item.quantity,
              unit_price: item.unit_price.to_f,
              total_price: item.total_price.to_f
            }
          end,
          
          # Return Requests
          return_requests: order.return_requests.map do |rr|
            {
              id: rr.id,
              request_type: rr.request_type,
              status: rr.status,
              reason: rr.reason,
              resolution_notes: rr.resolution_notes
            }
          end
        }
      end

      def transform_b2b_order(order)
        {
          id: order.id,
          order_type: "b2b",
          reference_number: order.reference_number,
          status: order.status,
          request_status: order.request_status,
          total_amount: order.total_amount.to_f,
          subtotal_amount: order.subtotal_amount.to_f,
          tax_amount: order.tax_amount.to_f,
          created_at: order.created_at.iso8601,
          
          # Buyer Info
          buyer_dealer_id: order.buyer_dealer_id,
          buyer_dealer_name: order.buyer_dealer&.full_name || order.buyer_dealer&.dealer_code,
          buyer_dealer_code: order.buyer_dealer&.dealer_code,
          
          # Seller Info
          seller_dealer_id: order.seller_dealer_id,
          seller_dealer_name: order.seller_dealer&.full_name || order.seller_dealer&.dealer_code,
          seller_dealer_code: order.seller_dealer&.dealer_code,
          
          # Source
          source_type: order.source_type,
          is_direct_buy: order.is_direct_buy,
          
          # Payment
          payment_method: order.payment_method,
          payment_status: order.payment_status,
          payment_token: order.payment_token,
          
          # Timestamps
          requested_at: order.requested_at&.iso8601,
          accepted_at: order.accepted_at&.iso8601,
          confirmed_at: order.confirmed_at&.iso8601,
          payment_confirmed_at: order.payment_confirmed_at&.iso8601,
          payment_link_sent_at: order.payment_link_sent_at&.iso8601,
          shipped_at: order.shipped_at&.iso8601,
          delivered_at: order.delivered_at&.iso8601,
          cancelled_at: order.cancelled_at&.iso8601,
          rejected_at: order.rejected_at&.iso8601,
          expired_at: order.expires_at&.iso8601,
          
          # Items
          b2b_order_items: order.b2b_order_items.map do |item|
            {
              id: item.id,
              product_name: item.product_variant&.product&.name || "Product",
              variant_sku: item.product_variant&.variant_sku,
              quantity: item.quantity,
              unit_price: item.unit_price.to_f,
              total_price: item.total_price.to_f,
              status: item.status
            }
          end
        }
      end

      def require_admin!
        unless current_admin.present?
          render json: { error: "Unauthorized. Admin access required." }, status: :unauthorized
        end
      end
    end
  end
end