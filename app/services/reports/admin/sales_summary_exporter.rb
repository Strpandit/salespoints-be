module Reports
  module Admin
    class SalesSummaryExporter < Reports::BaseExporter
      def generate
        range = date_range

        b2c_orders = Order.where(created_at: range).where.not(status: "cancelled")
        b2b_orders = B2bOrder.where(created_at: range).where.not(status: %w[cancelled rejected_request])

        total_orders   = b2c_orders.count + b2b_orders.count
        total_revenue  = b2c_orders.sum(:total_amount).to_f + b2b_orders.sum(:total_amount).to_f
        b2c_revenue    = b2c_orders.sum(:total_amount).to_f
        b2b_revenue    = b2b_orders.sum(:total_amount).to_f

        prepaid_b2c    = b2c_orders.where.not(payment_method: %w[cod postpaid]).sum(:total_amount).to_f
        postpaid_b2c   = b2c_orders.where(payment_method: %w[cod postpaid]).sum(:total_amount).to_f
        prepaid_b2b    = b2b_orders.where.not(payment_method: %w[cod postpaid]).sum(:total_amount).to_f
        postpaid_b2b   = b2b_orders.where(payment_method: %w[cod postpaid]).sum(:total_amount).to_f

        headers = ["Marketplace Sales Metric", "Value"]
        rows = [
          ["Report Period", "#{range.begin.strftime('%d %b %Y')} to #{range.end.strftime('%d %b %Y')}"],
          ["Gross Marketplace GMV (₹)", total_revenue.round(2)],
          ["Total Orders Executed", total_orders],
          ["B2C Sales Revenue (₹)", b2c_revenue.round(2)],
          ["B2B Sales Revenue (₹)", b2b_revenue.round(2)],
          ["Total Prepaid GMV (Online Gateway) (₹)", (prepaid_b2c + prepaid_b2b).round(2)],
          ["Total Postpaid GMV (COD) (₹)", (postpaid_b2c + postpaid_b2b).round(2)],
          ["Average Order Value (AOV) (₹)", total_orders.positive? ? (total_revenue / total_orders).round(2) : 0.0]
        ]

        {
          title: "Admin Marketplace Sales Summary Report",
          headers: headers,
          rows: rows
        }
      end
    end
  end
end
