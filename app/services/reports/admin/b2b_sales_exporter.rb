module Reports
  module Admin
    class B2bSalesExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Reference #", "Order Date", "Buyer Dealer Code", "Buyer Business Name", "Seller Dealer Code", "Seller Business Name", "Items Qty", "Subtotal (₹)", "Tax (₹)", "Total Amount (₹)", "Payment Mode", "Status"]
        rows = B2bOrder.where(created_at: range).includes(:buyer_dealer, :seller_dealer).order(created_at: :desc).map do |o|
          buyer_code = o.buyer_dealer&.dealer_code || "N/A"
          buyer_biz  = o.buyer_dealer&.dealer_profile&.business_name || o.buyer_dealer&.full_name || "Dealer"
          seller_code = o.seller_dealer&.dealer_code || "N/A"
          seller_biz  = o.seller_dealer&.dealer_profile&.business_name || o.seller_dealer&.full_name || "Dealer"
          pay_mode    = Reports::PrivacyFilter.format_payment_method(o.payment_method)

          [
            o.reference_number,
            o.created_at.strftime("%d %b %Y %H:%M"),
            buyer_code,
            buyer_biz,
            seller_code,
            seller_biz,
            o.b2b_order_items.sum(:quantity),
            o.subtotal_amount.to_f.round(2),
            o.tax_amount.to_f.round(2),
            o.total_amount.to_f.round(2),
            pay_mode,
            o.status.capitalize
          ]
        end

        { title: "Admin B2B Sales Register", headers: headers, rows: rows }
      end
    end
  end
end
