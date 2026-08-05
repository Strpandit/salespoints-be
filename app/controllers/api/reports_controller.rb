require "csv"
module Api
  class ReportsController < ApplicationController
    before_action :authorize_reports_access

    REPORT_TYPES = {
      "sales"    => "Sales Report",
      "revenue"  => "Revenue Report",
      "products" => "Products Report",
      "dealers"  => "Dealers Report",
      "payouts"  => "Payout Report"
    }.freeze

    # GET /reports/list
    def list
      data = if current_user_type == "AdminUser"
        [
          { type: "sales",    name: "Sales Report",    description: "All B2C + B2B orders, amounts, and statuses.",     icon: "shopping_cart" },
          { type: "revenue",  name: "Revenue Report",  description: "Revenue breakdown by period and order type.",      icon: "trending_up" },
          { type: "products", name: "Products Report", description: "Top selling products, stock and catalog summary.", icon: "package" },
          { type: "dealers",  name: "Dealers Report",  description: "Dealer performance, revenue, and order counts.",   icon: "store" },
          { type: "payouts",  name: "Payout Report",   description: "Dealer payout history and pending settlements.",   icon: "credit_card" }
        ]
      else
        [
          { type: "sales",   name: "My Sales Report",   description: "Your B2C and B2B order performance.",     icon: "shopping_cart" },
          { type: "revenue", name: "My Revenue Report", description: "Your revenue breakdown by period.",        icon: "trending_up" },
          { type: "payouts", name: "My Payout Report",  description: "Your payout history and pending amount.",  icon: "credit_card" }
        ]
      end
      render json: { success: true, data: data }
    end

    # GET /reports/summary
    def summary
      period      = params[:period].presence || "monthly"
      report_type = params[:report_type].presence || "sales"
      date_range  = date_range_for(period)

      data = if current_user_type == "AdminUser"
        admin_summary(report_type, date_range)
      else
        dealer_summary(report_type, date_range)
      end

      render json: { success: true, data: data }
    end

    # POST /reports/generate
    def generate
      report_type = params[:report_type].presence
      unless valid_report_type?(report_type)
        return render json: { success: false, error: "Invalid report type. Valid: #{REPORT_TYPES.keys.join(', ')}" }, status: :bad_request
      end

      period     = params[:period].presence || "monthly"
      date_range = date_range_for(period)

      rows = build_report_rows(report_type, date_range)

      csv_data = CSV.generate do |csv|
        csv << ["Report",    REPORT_TYPES[report_type]]
        csv << ["Period",    period.capitalize]
        csv << ["Generated", Time.current.strftime("%d %b %Y %H:%M")]
        csv << []
        csv << rows[:headers]
        rows[:data].each do |row|
          csv << row
        end
      end

      send_data(
        csv_data,
        filename: "#{report_type}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
        type: "text/csv; charset=utf-8",
        disposition: "attachment"
      )
    end

    # POST /reports/schedule
    def schedule
      render json: { success: true, message: "Scheduled reports are not yet configured." }
    end

    private

    def authorize_reports_access
      return if current_user_type.in?(%w[AdminUser Dealer])
      render json: { success: false, error: "Access denied" }, status: :forbidden
    end

    def valid_report_type?(type)
      REPORT_TYPES.key?(type.to_s)
    end

    # ─── SUMMARY BUILDERS ──────────────────────────────────────────────────────
    def admin_summary(report_type, date_range)
      case report_type
      when "sales", "revenue"
        b2c_orders = Order.where(created_at: date_range).where.not(status: "cancelled")
        b2b_orders = B2bOrder.where(created_at: date_range).where.not(status: %w[cancelled rejected_request])
        total_orders  = b2c_orders.count + b2b_orders.count
        total_revenue = b2c_orders.sum(:total_amount).to_f + b2b_orders.sum(:total_amount).to_f
        {
          totalOrders:    total_orders,
          totalRevenue:   total_revenue,
          avgOrderValue:  total_orders.positive? ? (total_revenue / total_orders).round(2) : 0,
          b2cOrders:      b2c_orders.count,
          b2bOrders:      b2b_orders.count,
          b2cRevenue:     b2c_orders.sum(:total_amount).to_f,
          b2bRevenue:     b2b_orders.sum(:total_amount).to_f,
          cancelledCount: Order.where(created_at: date_range, status: "cancelled").count +
                          B2bOrder.where(created_at: date_range, status: "cancelled").count
        }
      when "products"
        {
          totalCatalog:  Product.count,
          totalDealer:   DealerProduct.count,
          activeProducts: Product.where(is_active: true).count + DealerProduct.where(is_active: true).count,
          lowStock:      DealerProduct.where("stock_quantity <= 10 AND stock_quantity > 0").count,
          outOfStock:    DealerProduct.where(stock_quantity: 0).count
        }
      when "dealers"
        {
          totalDealers:  Dealer.count,
          activeDealers: Dealer.where(is_active: true).count,
          newDealers:    Dealer.where(created_at: date_range).count
        }
      when "payouts"
        {
          pendingPayouts:   DealerPayout.where(status: "pending").sum(:amount).to_f,
          completedPayouts: DealerPayout.where(status: "completed").sum(:amount).to_f,
          totalRequests:    DealerPayout.count
        }
      else
        {}
      end
    end

    def dealer_summary(report_type, date_range)
      dealer = current_dealer
      return {} unless dealer

      case report_type
      when "sales", "revenue"
        b2c = Order.where(seller_dealer_id: dealer.id, created_at: date_range).where.not(status: "cancelled")
        b2b = B2bOrder.where(seller_dealer_id: dealer.id, created_at: date_range).where.not(status: %w[cancelled rejected_request])
        total_orders  = b2c.count + b2b.count
        total_revenue = b2c.sum(:total_amount).to_f + b2b.sum(:total_amount).to_f
        {
          totalOrders:   total_orders,
          totalRevenue:  total_revenue,
          avgOrderValue: total_orders.positive? ? (total_revenue / total_orders).round(2) : 0,
          b2cOrders:     b2c.count,
          b2bOrders:     b2b.count
        }
      when "payouts"
        {
          pendingPayouts:   DealerPayout.where(dealer_id: dealer.id, status: "pending").sum(:amount).to_f,
          completedPayouts: DealerPayout.where(dealer_id: dealer.id, status: "completed").sum(:amount).to_f,
          totalRequests:    DealerPayout.where(dealer_id: dealer.id).count
        }
      else
        {}
      end
    end

    # ─── REPORT ROW BUILDERS ───────────────────────────────────────────────────
    def build_report_rows(report_type, date_range)
      case report_type
      when "sales"
        build_sales_rows(date_range)
      when "revenue"
        build_revenue_rows(date_range)
      when "products"
        build_products_rows
      when "dealers"
        build_dealers_rows(date_range)
      when "payouts"
        build_payouts_rows(date_range)
      else
        { headers: [], data: [] }
      end
    end

    def build_sales_rows(date_range)
      scope = if current_user_type == "AdminUser"
        Order.where(created_at: date_range)
      else
        Order.where(created_at: date_range, seller_dealer_id: current_dealer.id)
      end

      headers = ["Order Number", "Buyer", "Amount (₹)", "Payment Status", "Status", "Date"]
      data = scope.order(created_at: :desc).map do |o|
        buyer = o.buyer_type == "Account" ? Account.find_by(id: o.buyer_id)&.full_name : Dealer.find_by(id: o.buyer_id)&.full_name
        [o.order_number, buyer || "Unknown", o.total_amount.to_f.round(2), o.payment_status, o.status, o.created_at.strftime("%d %b %Y")]
      end

      if current_user_type == "AdminUser"
        b2b_scope = B2bOrder.where(created_at: date_range)
        b2b_scope.order(created_at: :desc).each do |o|
          buyer = o.buyer_dealer&.dealer_profile&.business_name || o.buyer_dealer&.full_name || "Dealer"
          data << [o.reference_number, buyer, o.total_amount.to_f.round(2), o.payment_status, o.status, o.created_at.strftime("%d %b %Y")]
        end
      end

      { headers: headers, data: data }
    end

    def build_revenue_rows(date_range)
      b2c = Order.where(created_at: date_range)
                 .where.not(status: "cancelled")
                 .group("DATE(created_at)")
                 .select("DATE(created_at) as date, SUM(total_amount) as total")
      b2b = B2bOrder.where(created_at: date_range)
                    .where.not(status: %w[cancelled rejected_request])
                    .group("DATE(created_at)")
                    .select("DATE(created_at) as date, SUM(total_amount) as total")

      combined = {}
      b2c.each { |r| combined[r.date.to_s] = (combined[r.date.to_s] || 0) + r.total.to_f }
      b2b.each { |r| combined[r.date.to_s] = (combined[r.date.to_s] || 0) + r.total.to_f }

      headers = ["Date", "Revenue (₹)"]
      data = combined.sort.map { |date, amount| [date, amount.round(2)] }
      { headers: headers, data: data }
    end

    def build_products_rows
      headers = ["Product Name", "SKU", "Category", "Brand", "Price (₹)", "Status", "Created"]
      data = Product.includes(:category, :brand).order(created_at: :desc).map do |p|
        [p.name, p.sku, p.category&.name, p.brand&.name, p.selling_price.to_f.round(2),
         p.is_active ? "Active" : "Inactive", p.created_at.strftime("%d %b %Y")]
      end
      { headers: headers, data: data }
    end

    def build_dealers_rows(date_range)
      headers = ["Dealer Code", "Name", "Business", "Email", "Orders", "Revenue (₹)", "Joined"]
      data = Dealer.order(created_at: :desc).map do |d|
        orders  = Order.where(seller_dealer_id: d.id, created_at: date_range).count
        revenue = Order.where(seller_dealer_id: d.id, created_at: date_range).sum(:total_amount).to_f
        [[d.first_name, d.last_name].compact.join(" ")]
        [d.dealer_code, [d.first_name, d.last_name].compact.join(" "), d.dealer_profile&.business_name, d.email, orders, revenue.round(2), d.created_at.strftime("%d %b %Y")]
      end
      { headers: headers, data: data }
    end

    def build_payouts_rows(date_range)
      scope = if current_user_type == "AdminUser"
        DealerPayout.includes(:dealer).where(created_at: date_range)
      else
        DealerPayout.where(dealer_id: current_dealer.id, created_at: date_range)
      end

      headers = current_user_type == "AdminUser" ?
        ["Payout ID", "Dealer", "Amount (₹)", "Status", "Requested At"] :
        ["Payout ID", "Amount (₹)", "Status", "Requested At"]

      data = scope.order(created_at: :desc).map do |p|
        if current_user_type == "AdminUser"
          [p.id, p.dealer&.dealer_profile&.business_name || p.dealer&.full_name, p.amount.to_f.round(2), p.status, p.created_at.strftime("%d %b %Y")]
        else
          [p.id, p.amount.to_f.round(2), p.status, p.created_at.strftime("%d %b %Y")]
        end
      end
      { headers: headers, data: data }
    end

    def date_range_for(period)
      case period.to_s
      when "today"     then Time.current.beginning_of_day..Time.current.end_of_day
      when "weekly"    then 1.week.ago.beginning_of_day..Time.current.end_of_day
      when "quarterly" then 3.months.ago.beginning_of_day..Time.current.end_of_day
      when "yearly"    then 1.year.ago.beginning_of_day..Time.current.end_of_day
      else                  1.month.ago.beginning_of_day..Time.current.end_of_day
      end
    end
  end
end
