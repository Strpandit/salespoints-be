module Reports
  module Vendor
    class OutstandingPaymentExporter < Reports::BaseExporter
      def generate
        dealer = current_user

        pending_orders = Order.where(seller_dealer_id: dealer.id, settlement_status: %w[on_hold pending]).where.not(status: "cancelled")
        total_outstanding = pending_orders.sum(:seller_settlement_amount).to_f

        headers = ["Order #", "Order Date", "Order Amount (₹)", "Commission (₹)", "Pending Settlement Amount (₹)", "Hold Status", "Settlement Due Date"]
        rows = pending_orders.order(created_at: :desc).map do |o|
          [o.order_number, o.created_at.strftime("%d %b %Y"), o.total_amount.to_f.round(2), o.commission_amount.to_f.round(2), o.seller_settlement_amount.to_f.round(2), o.settlement_status.capitalize, o.settlement_due_at&.strftime("%d %b %Y") || "Pending Delivery"]
        end

        rows << ["TOTAL OUTSTANDING", "", "", "", total_outstanding.round(2), "", ""]

        { title: "Vendor Outstanding Receivable Payment Report", headers: headers, rows: rows }
      end
    end
  end
end
