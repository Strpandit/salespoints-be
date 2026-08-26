module Reports
  module Vendor
    class B2cSalesExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Order Number", "Order Date", "Buyer Reference", "Total Items", "Total Value (₹)", "Payment Mode", "Status"]
        rows = Order.where(seller_dealer_id: dealer.id, created_at: range).order(created_at: :desc).map do |o|
          buyer_ref = Reports::PrivacyFilter.buyer_reference(o, scope: :vendor)
          pay_mode  = Reports::PrivacyFilter.format_payment_method(o.payment_method)
          [o.order_number, o.created_at.strftime("%d %b %Y"), buyer_ref, o.order_items.sum(:quantity), o.total_amount.to_f.round(2), pay_mode, o.status.capitalize]
        end

        { title: "Vendor B2C Sales Report", headers: headers, rows: rows }
      end
    end
  end
end
