module Reports
  module Vendor
    class SalesSummaryExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        return { title: "Vendor Sales Summary Report", headers: ["Metric", "Value"], rows: [] } unless dealer

        range = date_range

        b2c_orders = Order.where(seller_dealer_id: dealer.id, created_at: range).where.not(status: %w[cancelled pending])
        b2b_orders = B2bOrder.where(seller_dealer_id: dealer.id, created_at: range)
                      .where.not(status: %w[cancelled pending_request pending_payment rejected_request expired_request])

        total_orders   = b2c_orders.count + b2b_orders.count
        total_units    = b2c_orders.joins(:order_items).sum("order_items.quantity") + b2b_orders.joins(:b2b_order_items).sum("b2b_order_items.quantity")
        total_revenue  = b2c_orders.sum(:total_amount).to_f + b2b_orders.sum(:total_amount).to_f
        prepaid_sales  = b2c_orders.where.not(payment_method: %w[cod postpaid]).sum(:total_amount).to_f + b2b_orders.where.not(payment_method: %w[cod postpaid]).sum(:total_amount).to_f
        postpaid_sales = b2c_orders.where(payment_method: %w[cod postpaid]).sum(:total_amount).to_f + b2b_orders.where(payment_method: %w[cod postpaid]).sum(:total_amount).to_f

        headers = ["Metric", "Value"]
        rows = [
          ["Report Period", "#{range.begin.strftime('%d %b %Y')} to #{range.end.strftime('%d %b %Y')}"],
          ["Total Orders Executed", total_orders],
          ["Total Units Sold", total_units],
          ["Gross Sales Revenue (₹)", total_revenue.round(2)],
          ["Prepaid Sales Value (Online) (₹)", prepaid_sales.round(2)],
          ["Postpaid Sales Value (COD) (₹)", postpaid_sales.round(2)],
          ["B2C Orders Count", b2c_orders.count],
          ["B2B Orders Count", b2b_orders.count],
          ["Average Order Value (AOV) (₹)", total_orders.positive? ? (total_revenue / total_orders).round(2) : 0.0]
        ]

        {
          title: "Vendor Sales Summary Report",
          headers: headers,
          rows: rows
        }
      end
    end
  end
end
