module Reports
  module Admin
    class CodReconciliationExporter < Reports::BaseExporter
      def generate
        range = date_range

        cod_orders = Order.where(created_at: range, payment_method: %w[cod postpaid]).where.not(status: "cancelled")
        total_cod_value = cod_orders.sum(:total_amount).to_f
        delivered_cod_value = cod_orders.where(status: "delivered").sum(:total_amount).to_f
        pending_cod_value = total_cod_value - delivered_cod_value

        headers = ["COD Reconciliation Category", "Value"]
        rows = [
          ["Report Period", "#{range.begin.strftime('%d %b %Y')} to #{range.end.strftime('%d %b %Y')}"],
          ["Total Postpaid / COD Orders GMV (₹)", total_cod_value.round(2)],
          ["Delivered & Collected COD Cash (₹)", delivered_cod_value.round(2)],
          ["In-Transit / Uncollected COD Cash (₹)", pending_cod_value.round(2)]
        ]

        { title: "Admin COD Collections Reconciliation Report", headers: headers, rows: rows }
      end
    end
  end
end
