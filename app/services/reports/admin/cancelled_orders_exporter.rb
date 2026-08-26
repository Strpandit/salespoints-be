module Reports
  module Admin
    class CancelledOrdersExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Order #", "Channel", "Placed At", "Cancelled At", "Buyer Reference", "Seller Dealer", "Total Amount (₹)", "Cancellation Note"]
        rows = []

        Order.where(created_at: range, status: "cancelled").includes(:seller_dealer).order(cancelled_at: :desc).find_each do |o|
          buyer_info = Reports::PrivacyFilter.buyer_reference(o, scope: :admin)
          seller     = o.seller_dealer ? "#{o.seller_dealer.full_name} [#{o.seller_dealer.dealer_code}]" : "Marketplace"

          rows << [
            o.order_number,
            "B2C",
            o.created_at.strftime("%d %b %Y %H:%M"),
            o.cancelled_at&.strftime("%d %b %Y %H:%M") || "Cancelled",
            buyer_info,
            seller,
            o.total_amount.to_f.round(2),
            o.status_note.presence || "Cancelled by Customer / System"
          ]
        end

        B2bOrder.where(created_at: range, status: "cancelled").includes(:seller_dealer).order(cancelled_at: :desc).find_each do |o|
          buyer_info = Reports::PrivacyFilter.buyer_reference(o, scope: :admin)
          seller     = o.seller_dealer ? "#{o.seller_dealer.full_name} [#{o.seller_dealer.dealer_code}]" : "Marketplace"

          rows << [
            o.reference_number,
            "B2B",
            o.created_at.strftime("%d %b %Y %H:%M"),
            o.cancelled_at&.strftime("%d %b %Y %H:%M") || "Cancelled",
            buyer_info,
            seller,
            o.total_amount.to_f.round(2),
            o.status_note.presence || "Cancelled by Dealer / System"
          ]
        end

        { title: "Admin Cancelled Orders Register", headers: headers, rows: rows }
      end
    end
  end
end
