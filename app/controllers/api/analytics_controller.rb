module Api 
  class AnalyticsController < ApplicationController
    before_action :authorize_analytics_access

    def dashboard
      period = params[:period].presence || "monthly"
      date_range = date_range_for(period)
      sold_orders = scoped_orders(date_range)
      delivered_orders = sold_orders.where(status: "delivered")
      previous_range = previous_range_for(date_range)
      previous_orders = scoped_orders(previous_range)

      total_revenue = sold_orders.sum(:total_amount).to_f
      previous_revenue = previous_orders.sum(:total_amount).to_f
      total_orders = sold_orders.count
      previous_order_count = previous_orders.count

      data = {
        totalRevenue: total_revenue,
        totalOrders: total_orders,
        totalProducts: sold_orders.joins(:order_items).distinct.count("order_items.product_id"),
        totalCustomers: sold_orders.where(buyer_type: "Account").distinct.count(:buyer_id),
        revenueGrowth: growth_percentage(previous_revenue, total_revenue),
        ordersGrowth: growth_percentage(previous_order_count, total_orders),
        avgOrderValue: total_orders.positive? ? (total_revenue / total_orders).round(2) : 0,
        commissionEarned: sold_orders.sum(:commission_amount).to_f,
        pendingPayouts: current_user_type == "Dealer" ? current_dealer.dealer_payouts.where(status: "pending").sum(:amount).to_f : DealerPayout.where(status: "pending").sum(:amount).to_f,
        topProducts: top_products_for(sold_orders),
        recentOrders: recent_orders_for(sold_orders)
      }

      render json: { success: true, data: data }
    end

    def revenue
      render json: { success: true, data: { trend: scoped_orders(date_range_for(params[:period] || "monthly")).group("DATE(created_at)").sum(:total_amount) } }
    end

    def orders
      orders = scoped_orders(date_range_for(params[:period] || "monthly"))
      render json: { success: true, data: { total: orders.count, statuses: orders.group(:status).count } }
    end

    def payments
      orders = scoped_orders(date_range_for(params[:period] || "monthly"))
      render json: { success: true, data: { payment_statuses: orders.group(:payment_status).count } }
    end

    def sellers
      return render json: { success: true, data: [] } if current_user_type == "Dealer"

      data = Dealer.left_joins(:sales_orders)
                  .group("dealers.id")
                  .select("dealers.id, dealers.first_name, dealers.last_name, dealers.dealer_code, COUNT(orders.id) AS orders_count, COALESCE(SUM(orders.total_amount), 0) AS revenue_total")
                  .order("revenue_total DESC")
                  .limit(10)
                  .map do |dealer|
        {
          id: dealer.id,
          name: [dealer.first_name, dealer.last_name].compact.join(" ").presence || dealer.dealer_code,
          dealer_code: dealer.dealer_code,
          orders: dealer.orders_count.to_i,
          revenue: dealer.revenue_total.to_f
        }
      end

      render json: { success: true, data: data }
    end

    def products
      render json: { success: true, data: top_products_for(scoped_orders(date_range_for(params[:period] || "monthly"))) }
    end

    def customers
      orders = scoped_orders(date_range_for(params[:period] || "monthly")).where(buyer_type: "Account")
      data = orders.group(:buyer_id).count.map { |buyer_id, count| { buyer_id: buyer_id, orders: count } }
      render json: { success: true, data: data }
    end

    def real_time
      today = Time.current.beginning_of_day..Time.current.end_of_day
      orders = scoped_orders(today)
      render json: {
        success: true,
        data: {
          today_orders: orders.count,
          today_revenue: orders.sum(:total_amount).to_f,
          pending_payments: orders.where(payment_status: "pending").count,
          recent_orders: recent_orders_for(orders.limit(10))
        },
        timestamp: Time.current
      }
    end

    private

    def authorize_analytics_access
      return if current_user_type.in?(%w[AdminUser Dealer])

      render json: { success: false, error: "Access denied" }, status: :forbidden
    end

    def scoped_orders(date_range)
      scope = Order.where(created_at: date_range)
      scope = scope.where(seller_dealer_id: current_dealer.id) if current_user_type == "Dealer"
      scope
    end

    def top_products_for(orders)
      OrderItem.joins(:product, :order)
              .where(order_id: orders.select(:id))
              .group("products.id", "products.name")
              .select("products.id, products.name, SUM(order_items.quantity) AS units_total, COALESCE(SUM(order_items.total_price), 0) AS revenue_total")
              .order("revenue_total DESC")
              .limit(5)
              .map do |item|
        {
          name: item.name,
          revenue: item.revenue_total.to_f,
          units: item.units_total.to_i
        }
      end
    end

    def recent_orders_for(orders)
      orders.order(created_at: :desc).limit(5).map do |order|
        buyer_name =
          if order.buyer_type == "Dealer"
            Dealer.find_by(id: order.buyer_id)&.full_name
          else
            Account.find_by(id: order.buyer_id)&.full_name
          end

        {
          id: order.order_number,
          customer: buyer_name || "Customer",
          amount: order.total_amount.to_f,
          status: order.status,
          date: order.created_at
        }
      end
    end

    def date_range_for(period)
      case period
      when "weekly"
        1.week.ago.beginning_of_day..Time.current.end_of_day
      when "quarterly"
        3.months.ago.beginning_of_day..Time.current.end_of_day
      when "yearly"
        1.year.ago.beginning_of_day..Time.current.end_of_day
      else
        1.month.ago.beginning_of_day..Time.current.end_of_day
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