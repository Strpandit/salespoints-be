module Reports
  module Admin
    class DetailedSalesRegisterExporter < Reports::BaseExporter
      def generate
        range = date_range
        headers = ["Order #", "Channel", "Placed At", "Buyer Reference", "Seller Dealer", "Items Count", "Subtotal (₹)", "Tax (₹)", "Total Amount (₹)", "Payment Mode", "Payment Status", "Order Status"]
        rows = []

        Order.where(created_at: range).includes(:seller_dealer).order(created_at: :desc).find_each do |o|
          buyer_info = Reports::PrivacyFilter.buyer_reference(o, scope: :admin)
          seller     = o.seller_dealer ? "#{o.seller_dealer.full_name} [#{o.seller_dealer.dealer_code}]" : "Marketplace"
          pay_mode   = Reports::PrivacyFilter.format_payment_method(o.payment_method)

          rows << [
            o.order_number,
            "B2C",
            o.created_at.strftime("%d %b %Y %H:%M"),
            buyer_info,
            seller,
            o.order_items.sum(:quantity),
            o.subtotal_amount.to_f.round(2),
            o.tax_amount.to_f.round(2),
            o.total_amount.to_f.round(2),
            pay_mode,
            o.payment_status.capitalize,
            o.status.capitalize
          ]
        end

        B2bOrder.where(created_at: range).includes(:seller_dealer, :buyer_dealer).order(created_at: :desc).find_each do |o|
          buyer_info = Reports::PrivacyFilter.buyer_reference(o, scope: :admin)
          seller     = o.seller_dealer ? "#{o.seller_dealer.full_name} [#{o.seller_dealer.dealer_code}]" : "Marketplace"
          pay_mode   = Reports::PrivacyFilter.format_payment_method(o.payment_method)

          rows << [
            o.reference_number,
            "B2B",
            o.created_at.strftime("%d %b %Y %H:%M"),
            buyer_info,
            seller,
            o.b2b_order_items.sum(:quantity),
            o.subtotal_amount.to_f.round(2),
            o.tax_amount.to_f.round(2),
            o.total_amount.to_f.round(2),
            pay_mode,
            o.payment_status.capitalize,
            o.status.capitalize
          ]
        end

        { title: "Admin Detailed Sales Register", headers: headers, rows: rows }
      end
    end
  end
end
