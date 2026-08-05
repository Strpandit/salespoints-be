require 'csv'
module Api
  class AnalyticsController < ApplicationController
    before_action :authorize_analytics_access

    # ─── ADMIN DASHBOARD ───────────────────────────────────────────────────────
    def dashboard
      period = params[:period].presence || "monthly"
      date_range = date_range_for(period)
      previous_range = previous_range_for(date_range)

      # B2C + B2B Orders for the period
      b2c_orders = Order.where(created_at: date_range)
      b2b_orders = B2bOrder.where(created_at: date_range)

      prev_b2c_orders = Order.where(created_at: previous_range)
      prev_b2b_orders = B2bOrder.where(created_at: previous_range)

      b2c_revenue = b2c_orders.where.not(status: "cancelled").sum(:total_amount).to_f
      b2b_revenue = b2b_orders.where.not(status: %w[cancelled rejected_request]).sum(:total_amount).to_f
      total_revenue = b2c_revenue + b2b_revenue

      prev_b2c_revenue = prev_b2c_orders.where.not(status: "cancelled").sum(:total_amount).to_f
      prev_b2b_revenue = prev_b2b_orders.where.not(status: %w[cancelled rejected_request]).sum(:total_amount).to_f
      previous_revenue = prev_b2c_revenue + prev_b2b_revenue

      total_orders_count = b2c_orders.count + b2b_orders.count
      previous_orders_count = prev_b2c_orders.count + prev_b2b_orders.count

      # Staff / Dealers / Customers
      staff_count    = AdminUser.count
      dealer_count   = Dealer.count
      customer_count = Account.count
      total_users    = staff_count + dealer_count + customer_count

      prev_staff     = AdminUser.where("created_at <= ?", previous_range.end).count
      prev_dealers   = Dealer.where("created_at <= ?", previous_range.end).count
      prev_customers = Account.where("created_at <= ?", previous_range.end).count
      prev_total_users = prev_staff + prev_dealers + prev_customers

      # Products breakdown (catalog + dealer)
      catalog_products = Product.count
      dealer_prods     = DealerProduct.count
      total_products   = catalog_products + dealer_prods
      active_products  = Product.where(is_active: true).count + DealerProduct.where(is_active: true).count
      inactive_products = [total_products - active_products, 0].max

      prev_products = Product.where("created_at <= ?", previous_range.end).count +
                      DealerProduct.where("created_at <= ?", previous_range.end).count

      avg_order_value = total_orders_count.positive? ? (total_revenue / total_orders_count).round(2) : 0

      # Revenue trend (grouped by date)
      revenue_trend = build_revenue_trend(date_range)

      # Orders by status
      b2c_by_status = b2c_orders.group(:status).count
      b2b_by_status = b2b_orders.group(:status).count
      orders_by_status = b2c_by_status.merge(b2b_by_status) { |_k, a, b| a + b }

      # Payment method breakdown
      payment_breakdown = build_payment_breakdown(b2c_orders, b2b_orders)

      # Top sellers (dealers by revenue)
      top_sellers = build_top_sellers(date_range)

      data = {
        totalRevenue:    total_revenue,
        totalOrders:     total_orders_count,
        totalProducts:   total_products,
        totalCustomers:  customer_count,
        avgOrderValue:   avg_order_value,
        revenueGrowth:   growth_percentage(previous_revenue, total_revenue),
        ordersGrowth:    growth_percentage(previous_orders_count, total_orders_count),
        usersGrowth:     growth_percentage(prev_total_users, total_users),
        productsGrowth:  growth_percentage(prev_products, total_products),
        users: {
          total:     total_users,
          staff:     staff_count,
          dealers:   dealer_count,
          customers: customer_count
        },
        products: {
          total:    total_products,
          active:   active_products,
          inactive: inactive_products,
          catalog:  catalog_products,
          dealer:   dealer_prods
        },
        revenueTrend:      revenue_trend,
        ordersByStatus:    orders_by_status,
        paymentBreakdown:  payment_breakdown,
        topSellers:        top_sellers,
        topProducts:       top_products_combined(date_range),
        recentOrders:      recent_orders_combined
      }

      render json: { success: true, data: data }
    end

    # ─── DEALER DASHBOARD ──────────────────────────────────────────────────────
    def dealer_dashboard
      return render json: { success: false, error: "Access denied" }, status: :forbidden unless current_dealer

      period = params[:period].presence || "monthly"
      date_range = date_range_for(period)
      previous_range = previous_range_for(date_range)

      dealer = current_dealer

      # B2C sales orders where the seller is this dealer
      b2c_orders = Order.where(seller_dealer_id: dealer.id, created_at: date_range)
      prev_b2c = Order.where(seller_dealer_id: dealer.id, created_at: previous_range)

      # B2B orders where this dealer is the seller
      b2b_orders = B2bOrder.where(seller_dealer_id: dealer.id, created_at: date_range)
      prev_b2b = B2bOrder.where(seller_dealer_id: dealer.id, created_at: previous_range)

      b2c_revenue = b2c_orders.where.not(status: "cancelled").sum(:total_amount).to_f
      b2b_revenue = b2b_orders.where.not(status: %w[cancelled rejected_request]).sum(:total_amount).to_f
      total_revenue = b2c_revenue + b2b_revenue

      prev_b2c_revenue = prev_b2c.where.not(status: "cancelled").sum(:total_amount).to_f
      prev_b2b_revenue = prev_b2b.where.not(status: %w[cancelled rejected_request]).sum(:total_amount).to_f
      previous_revenue = prev_b2c_revenue + prev_b2b_revenue

      total_orders = b2c_orders.count + b2b_orders.count
      prev_orders = prev_b2c.count + prev_b2b.count

      avg_order_value = total_orders.positive? ? (total_revenue / total_orders).round(2) : 0

      # Inventory / products
      dealer_products = DealerProduct.where(dealer_id: dealer.id)
      total_inventory  = dealer_products.sum(:stock_quantity).to_i
      total_listed     = dealer_products.count
      active_listed    = dealer_products.where(is_active: true).count
      low_stock_count  = dealer_products.where("stock_quantity <= 10 AND stock_quantity > 0").count
      out_of_stock     = dealer_products.where(stock_quantity: 0).count

      prev_products = DealerProduct.where(dealer_id: dealer.id, created_at: ..previous_range.end).count

      # Pending payouts
      pending_payouts = DealerPayout.where(dealer_id: dealer.id, status: "pending").sum(:amount).to_f rescue 0.0
      total_paid_out = DealerPayout.where(dealer_id: dealer.id, status: "completed").sum(:amount).to_f rescue 0.0

      # Orders by status
      b2c_by_status = b2c_orders.group(:status).count
      b2b_by_status = b2b_orders.group(:status).count
      orders_by_status = b2c_by_status.merge(b2b_by_status) { |_k, a, b| a + b }

      # Revenue trend
      revenue_trend = build_dealer_revenue_trend(dealer.id, date_range)

      # Top products for this dealer
      top_prods = dealer_top_products(dealer.id, date_range)

      # Recent orders
      recent_b2c = b2c_orders.order(created_at: :desc).limit(5).map do |o|
        {
          id: o.order_number,
          order_number: o.order_number,
          customer: Account.find_by(id: o.buyer_id)&.full_name || "Customer",
          amount: o.total_amount.to_f,
          status: o.status,
          date: o.created_at,
          type: "B2C",
          items: (o.order_items.count rescue 1)
        }
      end

      recent_b2b = b2b_orders.order(created_at: :desc).limit(5).map do |o|
        {
          id: o.reference_number,
          order_number: o.reference_number,
          customer: o.buyer_dealer&.dealer_profile&.business_name || o.buyer_dealer&.full_name || "Dealer",
          amount: o.total_amount.to_f,
          status: o.status,
          date: o.created_at,
          type: "B2B",
          items: (o.b2b_order_items.count rescue 1)
        }
      end

      recent_orders = (recent_b2c + recent_b2b).sort_by { |o| o[:date] }.reverse.first(10)

      data = {
        totalRevenue:   total_revenue,
        totalOrders:    total_orders,
        avgOrderValue:  avg_order_value,
        pendingPayout:  pending_payouts,
        totalPaidOut:   total_paid_out,
        revenueGrowth:  growth_percentage(previous_revenue, total_revenue),
        ordersGrowth:   growth_percentage(prev_orders, total_orders),
        productsGrowth: growth_percentage(prev_products, total_listed),
        inventory: {
          total:       total_inventory,
          listed:      total_listed,
          active:      active_listed,
          lowStock:    low_stock_count,
          outOfStock:  out_of_stock
        },
        ordersByStatus:  orders_by_status,
        revenueTrend:    revenue_trend,
        topProducts:     top_prods,
        recentOrders:    recent_orders
      }

      render json: { success: true, data: data }
    end

    # ─── OTHER ENDPOINTS ───────────────────────────────────────────────────────
    def revenue
      range = date_range_for(params[:period] || "monthly")
      b2c_trend = Order.where(created_at: range).group("DATE(created_at)").sum(:total_amount)
      b2b_trend = B2bOrder.where(created_at: range).group("DATE(created_at)").sum(:total_amount)
      combined = b2c_trend.merge(b2b_trend) { |_key, v1, v2| v1 + v2 }
      render json: { success: true, data: { trend: combined } }
    end

    def orders
      range = date_range_for(params[:period] || "monthly")
      total = Order.where(created_at: range).count + B2bOrder.where(created_at: range).count
      render json: { success: true, data: { total: total } }
    end

    def payments
      range = date_range_for(params[:period] || "monthly")
      b2c_p = Order.where(created_at: range).group(:payment_status).count
      b2b_p = B2bOrder.where(created_at: range).group(:payment_status).count
      combined = b2c_p.merge(b2b_p) { |_key, v1, v2| v1 + v2 }
      render json: { success: true, data: { payment_statuses: combined } }
    end

    def sellers
      return render json: { success: true, data: [] } if current_user_type == "Dealer"

      range = date_range_for(params[:period] || "monthly")
      data = build_top_sellers(range)
      render json: { success: true, data: data }
    end

    def products
      render json: { success: true, data: top_products_combined(date_range_for(params[:period] || "monthly")) }
    end

    def customers
      orders = Order.where(created_at: date_range_for(params[:period] || "monthly")).where(buyer_type: "Account")
      data = orders.group(:buyer_id).count.map { |buyer_id, count| { buyer_id: buyer_id, orders: count } }
      render json: { success: true, data: data }
    end

    def real_time
      today = Time.current.beginning_of_day..Time.current.end_of_day
      orders_count  = Order.where(created_at: today).count + B2bOrder.where(created_at: today).count
      revenue_sum   = Order.where(created_at: today).sum(:total_amount).to_f +
                      B2bOrder.where(created_at: today).sum(:total_amount).to_f
      pending_count = Order.where(created_at: today, payment_status: "pending").count +
                      B2bOrder.where(created_at: today, payment_status: "pending_payment").count

      render json: {
        success: true,
        data: {
          today_orders:     orders_count,
          today_revenue:    revenue_sum,
          pending_payments: pending_count,
          recent_orders:    recent_orders_combined
        },
        timestamp: Time.current
      }
    end

    private

    def authorize_analytics_access
      return if current_user_type.in?(%w[AdminUser Dealer])
      render json: { success: false, error: "Access denied" }, status: :forbidden
    end

    # ─── REVENUE TREND ─────────────────────────────────────────────────────────
    def build_revenue_trend(date_range)
      b2c = Order.where(created_at: date_range)
                 .where.not(status: "cancelled")
                 .group("DATE(created_at)")
                 .sum(:total_amount)
      b2b = B2bOrder.where(created_at: date_range)
                    .where.not(status: %w[cancelled rejected_request])
                    .group("DATE(created_at)")
                    .sum(:total_amount)

      merged = b2c.merge(b2b) { |_k, a, b| a + b }
      merged.sort.map do |date, amount|
        { date: date.to_s, amount: amount.to_f, label: Date.parse(date.to_s).strftime("%d %b") }
      end
    end

    def build_dealer_revenue_trend(dealer_id, date_range)
      b2c = Order.where(seller_dealer_id: dealer_id, created_at: date_range)
                 .where.not(status: "cancelled")
                 .group("DATE(created_at)")
                 .sum(:total_amount)
      b2b = B2bOrder.where(seller_dealer_id: dealer_id, created_at: date_range)
                    .where.not(status: %w[cancelled rejected_request])
                    .group("DATE(created_at)")
                    .sum(:total_amount)

      merged = b2c.merge(b2b) { |_k, a, b| a + b }
      merged.sort.map do |date, amount|
        { date: date.to_s, amount: amount.to_f, label: Date.parse(date.to_s).strftime("%d %b") }
      end
    end

    # ─── TOP SELLERS ───────────────────────────────────────────────────────────
    def build_top_sellers(date_range)
      b2c_data = Order.where(created_at: date_range, seller_dealer_id: Dealer.select(:id))
                      .where.not(status: "cancelled")
                      .group(:seller_dealer_id)
                      .select("seller_dealer_id, COUNT(*) as order_count, SUM(total_amount) as revenue")

      b2b_data = B2bOrder.where(created_at: date_range)
                         .where.not(status: %w[cancelled rejected_request])
                         .group(:seller_dealer_id)
                         .select("seller_dealer_id, COUNT(*) as order_count, SUM(total_amount) as revenue")

      combined = {}
      b2c_data.each do |r|
        combined[r.seller_dealer_id] ||= { orders: 0, revenue: 0.0 }
        combined[r.seller_dealer_id][:orders]  += r.order_count.to_i
        combined[r.seller_dealer_id][:revenue] += r.revenue.to_f
      end
      b2b_data.each do |r|
        combined[r.seller_dealer_id] ||= { orders: 0, revenue: 0.0 }
        combined[r.seller_dealer_id][:orders]  += r.order_count.to_i
        combined[r.seller_dealer_id][:revenue] += r.revenue.to_f
      end

      combined.sort_by { |_, v| -v[:revenue] }.first(10).map do |dealer_id, stats|
        d = Dealer.find_by(id: dealer_id)
        next unless d
        {
          id:          d.id,
          name:        d.dealer_profile&.business_name.presence || [d.first_name, d.last_name].compact.join(" ").presence || d.dealer_code,
          dealer_code: d.dealer_code,
          orders:      stats[:orders],
          revenue:     stats[:revenue].round(2)
        }
      end.compact
    end

    # ─── PAYMENT BREAKDOWN ─────────────────────────────────────────────────────
    def build_payment_breakdown(b2c_orders, b2b_orders)
      b2c_methods = b2c_orders.group(:payment_method).count rescue {}
      b2b_methods = b2b_orders.group(:payment_mode).count   rescue {}

      combined = b2c_methods.transform_keys(&:to_s)
      b2b_methods.each do |method, count|
        combined[method.to_s] = (combined[method.to_s] || 0) + count
      end

      total = combined.values.sum.to_f
      combined.sort_by { |_, v| -v }.map do |method, count|
        {
          method:     method.presence || "unknown",
          count:      count,
          percentage: total.positive? ? ((count / total) * 100).round(1) : 0
        }
      end
    end

    # ─── TOP PRODUCTS ──────────────────────────────────────────────────────────
    def top_products_combined(date_range)
      b2c_items = OrderItem.joins(:order, product_variant: :product)
                          .where(orders: { created_at: date_range })
                          .group("products.name")
                          .select("products.name as product_title, SUM(order_items.quantity) as units_total, SUM(order_items.total_price) as revenue_total")
      
      b2b_items = B2bOrderItem.joins(:b2b_order)
                              .joins("INNER JOIN dealer_products ON dealer_products.id = b2b_order_items.dealer_product_id")
                              .joins("INNER JOIN products ON products.id = dealer_products.product_id")
                              .where(b2b_orders: { created_at: date_range })
                              .group("products.name")
                              .select("products.name as product_title, SUM(b2b_order_items.quantity) as units_total, SUM(b2b_order_items.total_price) as revenue_total")
      
      combined = {}
      
      b2c_items.each do |item|
        combined[item.product_title] ||= { revenue: 0, units: 0 }
        combined[item.product_title][:revenue] += item.revenue_total.to_f
        combined[item.product_title][:units] += item.units_total.to_i
      end
      
      b2b_items.each do |item|
        combined[item.product_title] ||= { revenue: 0, units: 0 }
        combined[item.product_title][:revenue] += item.revenue_total.to_f
        combined[item.product_title][:units] += item.units_total.to_i
      end
      
      sorted = combined.sort_by { |_, v| -v[:revenue] }.first(5)
      
      if sorted.empty?
        Product.limit(5).map { |p| { name: p.name, revenue: 0.0, units: 0 } }
      else
        sorted.map do |name, data|
          {
            name:    name || "Product",
            revenue: data[:revenue].round(2),
            units:   data[:units]
          }
        end
      end
    end

    def dealer_top_products(dealer_id, date_range)
      b2c_items = OrderItem.joins(:order, product_variant: :product)
                          .where(orders: { created_at: date_range, seller_dealer_id: dealer_id })
                          .group("products.name")
                          .select("products.name as product_title, SUM(order_items.quantity) as units_total, SUM(order_items.total_price) as revenue_total")
      
      b2b_items = B2bOrderItem.joins(:b2b_order)
                              .joins("INNER JOIN dealer_products ON dealer_products.id = b2b_order_items.dealer_product_id")
                              .joins("INNER JOIN products ON products.id = dealer_products.product_id")
                              .where(b2b_orders: { created_at: date_range, seller_dealer_id: dealer_id })
                              .group("products.name")
                              .select("products.name as product_title, SUM(b2b_order_items.quantity) as units_total, SUM(b2b_order_items.total_price) as revenue_total")
      
      combined = {}
      
      b2c_items.each do |item|
        combined[item.product_title] ||= { revenue: 0, units: 0 }
        combined[item.product_title][:revenue] += item.revenue_total.to_f
        combined[item.product_title][:units] += item.units_total.to_i
      end
      
      b2b_items.each do |item|
        combined[item.product_title] ||= { revenue: 0, units: 0 }
        combined[item.product_title][:revenue] += item.revenue_total.to_f
        combined[item.product_title][:units] += item.units_total.to_i
      end
      
      sorted = combined.sort_by { |_, v| -v[:revenue] }.first(5)
      
      sorted.map do |name, data|
        {
          name:    name || "Product",
          revenue: data[:revenue].round(2),
          units:   data[:units]
        }
      end
    end

    # ─── RECENT ORDERS (ADMIN) ─────────────────────────────────────────────────
    def recent_orders_combined
      b2c = Order.order(created_at: :desc).limit(5).map do |o|
        buyer_name = if o.buyer_type == "Dealer"
                       Dealer.find_by(id: o.buyer_id)&.full_name || Dealer.find_by(id: o.buyer_id)&.email
                     else
                       Account.find_by(id: o.buyer_id)&.full_name || Account.find_by(id: o.buyer_id)&.email
                     end
        {
          id:           o.order_number,
          order_number: o.order_number,
          customer:     buyer_name || "Customer",
          amount:       o.total_amount.to_f,
          status:       o.status,
          date:         o.created_at,
          type:         "B2C",
          items:        (o.order_items.count rescue 1)
        }
      end

      b2b = B2bOrder.order(created_at: :desc).limit(5).map do |o|
        buyer_name = o.buyer_dealer&.dealer_profile&.business_name || o.buyer_dealer&.full_name || "Dealer"
        {
          id:           o.reference_number,
          order_number: o.reference_number,
          customer:     buyer_name,
          amount:       o.total_amount.to_f,
          status:       o.status,
          date:         o.created_at,
          type:         "B2B",
          items:        (o.b2b_order_items.count rescue 1)
        }
      end

      (b2c + b2b).sort_by { |item| item[:date] }.reverse.first(10)
    end

    # ─── DATE HELPERS ──────────────────────────────────────────────────────────
    def date_range_for(period)
      case period.to_s
      when "today"     then Time.current.beginning_of_day..Time.current.end_of_day
      when "weekly"    then 1.week.ago.beginning_of_day..Time.current.end_of_day
      when "quarterly" then 3.months.ago.beginning_of_day..Time.current.end_of_day
      when "yearly"    then 1.year.ago.beginning_of_day..Time.current.end_of_day
      else                  1.month.ago.beginning_of_day..Time.current.end_of_day
      end
    end

    def previous_range_for(current_range)
      duration = current_range.end - current_range.begin
      (current_range.begin - duration)..current_range.begin
    end

    def growth_percentage(previous_value, current_value)
      return current_value.positive? ? 100.0 : 0.0 if previous_value.to_f.zero?
      (((current_value.to_f - previous_value.to_f) / previous_value.to_f) * 100).round(2)
    end
  end
end