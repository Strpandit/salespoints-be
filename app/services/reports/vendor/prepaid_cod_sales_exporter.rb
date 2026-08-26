module Reports
  module Vendor
    class PrepaidCodSalesExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Order Reference", "Order Type", "Buyer Reference", "Payment Mode", "Amount (₹)", "Status", "Order Date"]
        rows = []

        Order.where(seller_dealer_id: dealer.id, created_at: range).order(created_at: :desc).find_each do |o|
          buyer_ref = Reports::PrivacyFilter.buyer_reference(o, scope: :vendor)
          pay_mode  = Reports::PrivacyFilter.format_payment_method(o.payment_method)
          rows << [o.order_number, "B2C", buyer_ref, pay_mode, o.total_amount.to_f.round(2), o.status.capitalize, o.created_at.strftime("%d %b %Y %H:%M")]
        end

        B2bOrder.where(seller_dealer_id: dealer.id, created_at: range).order(created_at: :desc).find_each do |o|
          buyer_ref = Reports::PrivacyFilter.buyer_reference(o, scope: :vendor)
          pay_mode  = Reports::PrivacyFilter.format_payment_method(o.payment_method)
          rows << [o.reference_number, "B2B", buyer_ref, pay_mode, o.total_amount.to_f.round(2), o.status.capitalize, o.created_at.strftime("%d %b %Y %H:%M")]
        end

        {
          title: "Vendor Prepaid vs Postpaid Sales Report",
          headers: headers,
          rows: rows
        }
      end
    end
  end
end
