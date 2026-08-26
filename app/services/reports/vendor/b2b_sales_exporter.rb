module Reports
  module Vendor
    class B2bSalesExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Reference Number", "Order Date", "Dealer Code Reference", "Total Items", "Subtotal (₹)", "Tax (₹)", "Total Amount (₹)", "Payment Mode", "Status"]
        rows = B2bOrder.where(seller_dealer_id: dealer.id, created_at: range).order(created_at: :desc).map do |o|
          dealer_code = o.buyer_dealer&.dealer_code || "Dealer"
          pay_mode    = Reports::PrivacyFilter.format_payment_method(o.payment_method)
          [o.reference_number, o.created_at.strftime("%d %b %Y"), dealer_code, o.b2b_order_items.sum(:quantity), o.subtotal_amount.to_f.round(2), o.tax_amount.to_f.round(2), o.total_amount.to_f.round(2), pay_mode, o.status.capitalize]
        end

        { title: "Vendor B2B Sales Report", headers: headers, rows: rows }
      end
    end
  end
end
