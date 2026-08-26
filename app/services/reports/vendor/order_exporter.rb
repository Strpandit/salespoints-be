module Reports
  module Vendor
    class OrderExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Order #", "Type", "Order Date", "Payment Mode", "Payment Status", "Order Status", "Total Amount (₹)"]
        rows = []

        Order.where(seller_dealer_id: dealer.id, created_at: range).order(created_at: :desc).find_each do |o|
          pay_mode = Reports::PrivacyFilter.format_payment_method(o.payment_method)
          rows << [o.order_number, "B2C", o.created_at.strftime("%d %b %Y %H:%M"), pay_mode, o.payment_status.capitalize, o.status.capitalize, o.total_amount.to_f.round(2)]
        end

        B2bOrder.where(seller_dealer_id: dealer.id, created_at: range).order(created_at: :desc).find_each do |o|
          pay_mode = Reports::PrivacyFilter.format_payment_method(o.payment_method)
          rows << [o.reference_number, "B2B", o.created_at.strftime("%d %b %Y %H:%M"), pay_mode, o.payment_status.capitalize, o.status.capitalize, o.total_amount.to_f.round(2)]
        end

        { title: "Vendor Order Report", headers: headers, rows: rows }
      end
    end
  end
end
