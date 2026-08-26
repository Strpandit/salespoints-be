module Reports
  module Admin
    class ProfitabilityExporter < Reports::BaseExporter
      def generate
        range = date_range

        orders = Order.where(created_at: range).where.not(status: "cancelled")
        total_gmv   = orders.sum(:total_amount).to_f
        total_comm  = orders.sum(:commission_amount).to_f
        total_refunds = ReturnRequest.where(created_at: range, status: "completed").sum(:refund_amount).to_f
        net_platform_profit = total_comm - total_refunds

        headers = ["Financial Performance Metric", "Value"]
        rows = [
          ["Report Period", "#{range.begin.strftime('%d %b %Y')} to #{range.end.strftime('%d %b %Y')}"],
          ["Gross Marketplace GMV (₹)", total_gmv.round(2)],
          ["Gross Commission Fee Earnings (₹)", total_comm.round(2)],
          ["Refunds & Return Deductions (₹)", total_refunds.round(2)],
          ["Net Platform Contribution Profit (₹)", net_platform_profit.round(2)]
        ]

        { title: "Admin Profitability & Contribution Margin Report", headers: headers, rows: rows }
      end
    end
  end
end
