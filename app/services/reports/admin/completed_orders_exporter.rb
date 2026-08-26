module Reports
  module Admin
    class CompletedOrdersExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Order #", "Channel", "Placed At", "Delivered At", "Buyer Reference", "Seller Dealer", "Total Amount (₹)", "Payment Status"]
        rows = []

        Order.where(created_at: range, status: "delivered").includes(:seller_dealer).order(delivered_at: :desc).find_each do |o|
          buyer_info = Reports::PrivacyFilter.buyer_reference(o, scope: :admin)
          seller     = o.seller_dealer ? "#{o.seller_dealer.full_name} [#{o.seller_dealer.dealer_code}]" : "Marketplace"

          rows << [
            o.order_number,
            "B2C",
            o.created_at.strftime("%d %b %Y %H:%M"),
            o.delivered_at&.strftime("%d %b %Y %H:%M") || "Delivered",
            buyer_info,
            seller,
            o.total_amount.to_f.round(2),
            o.payment_status.capitalize
          ]
        end

        B2bOrder.where(created_at: range, status: "delivered").includes(:seller_dealer).order(delivered_at: :desc).find_each do |o|
          buyer_info = Reports::PrivacyFilter.buyer_reference(o, scope: :admin)
          seller     = o.seller_dealer ? "#{o.seller_dealer.full_name} [#{o.seller_dealer.dealer_code}]" : "Marketplace"

          rows << [
            o.reference_number,
            "B2B",
            o.created_at.strftime("%d %b %Y %H:%M"),
            o.delivered_at&.strftime("%d %b %Y %H:%M") || "Delivered",
            buyer_info,
            seller,
            o.total_amount.to_f.round(2),
            o.payment_status.capitalize
          ]
        end

        { title: "Admin Completed & Delivered Orders Log", headers: headers, rows: rows }
      end
    end
  end
end
