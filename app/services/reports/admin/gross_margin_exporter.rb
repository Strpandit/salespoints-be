module Reports
  module Admin
    class GrossMarginExporter < Reports::BaseExporter
      def generate
        range = date_range

        b2c_orders = Order.where(created_at: range).where.not(status: "cancelled")
        total_gmv   = b2c_orders.sum(:total_amount).to_f
        total_comm  = b2c_orders.sum(:commission_amount).to_f
        total_settle = b2c_orders.sum(:seller_settlement_amount).to_f
        gross_margin_pct = total_gmv.positive? ? ((total_comm / total_gmv) * 100).round(2) : 0.0

        headers = ["Financial Metric", "Value"]
        rows = [
          ["Report Period", "#{range.begin.strftime('%d %b %Y')} to #{range.end.strftime('%d %b %Y')}"],
          ["Gross GMV (₹)", total_gmv.round(2)],
          ["Total Dealer Settlement Cost (₹)", total_settle.round(2)],
          ["Marketplace Gross Commission Earnings (₹)", total_comm.round(2)],
          ["Gross Margin Rate (%)", "#{gross_margin_pct}%"]
        ]

        { title: "Admin Gross Margin Report", headers: headers, rows: rows }
      end
    end
  end
end
