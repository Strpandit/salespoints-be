module Reports
  module Admin
    class PaymentReconciliationExporter < Reports::BaseExporter
      def generate
        range = date_range

        prepaid_orders = Order.where(created_at: range).where.not(payment_method: %w[cod postpaid], status: "cancelled")
        total_gateway_collected = prepaid_orders.sum(:total_amount).to_f
        total_attempts = PaymentAttempt.where(created_at: range, status: "paid").sum(:amount).to_f

        headers = ["Reconciliation Metric", "Value"]
        rows = [
          ["Report Period", "#{range.begin.strftime('%d %b %Y')} to #{range.end.strftime('%d %b %Y')}"],
          ["Successful Gateway Collections (₹)", total_attempts.round(2)],
          ["Fulfilled Prepaid Orders GMV (₹)", total_gateway_collected.round(2)],
          ["Payment Reconciliation Variance (₹)", (total_attempts - total_gateway_collected).round(2)]
        ]

        { title: "Admin Payment Reconciliation Statement", headers: headers, rows: rows }
      end
    end
  end
end
