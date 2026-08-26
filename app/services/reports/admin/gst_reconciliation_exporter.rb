module Reports
  module Admin
    class GstReconciliationExporter < Reports::BaseExporter
      def generate
        range = date_range

        orders = Order.where(created_at: range).where.not(status: "cancelled")
        b2b    = B2bOrder.where(created_at: range).where.not(status: %w[cancelled rejected_request])

        sales_tax    = orders.sum(:tax_amount).to_f
        purchase_tax = b2b.sum(:tax_amount).to_f
        net_liability = sales_tax - purchase_tax

        headers = ["GST Tax Category", "Amount (₹)"]
        rows = [
          ["Report Period", "#{range.begin.strftime('%d %b %Y')} to #{range.end.strftime('%d %b %Y')}"],
          ["Output Sales GST Liability (GSTR-1) (₹)", sales_tax.round(2)],
          ["Input Tax Credit / Purchase GST (GSTR-3B) (₹)", purchase_tax.round(2)],
          ["Net GST Payable / Liability Balance (₹)", net_liability.round(2)]
        ]

        { title: "Admin GST Reconciliation Statement", headers: headers, rows: rows }
      end
    end
  end
end
