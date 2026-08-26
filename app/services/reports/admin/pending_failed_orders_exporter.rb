module Reports
  module Admin
    class PendingFailedOrdersExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Order #", "Channel", "Placed At", "Buyer Reference", "Seller Dealer", "Total Amount (₹)", "Payment Status", "Pending Reason"]
        rows = []

        Order.where(created_at: range, status: %w[pending processing pending_payment]).includes(:seller_dealer).order(created_at: :desc).find_each do |o|
          buyer_info = Reports::PrivacyFilter.buyer_reference(o, scope: :admin)
          seller     = o.seller_dealer ? "#{o.seller_dealer.full_name} [#{o.seller_dealer.dealer_code}]" : "Marketplace"

          rows << [
            o.order_number,
            "B2C",
            o.created_at.strftime("%d %b %Y %H:%M"),
            buyer_info,
            seller,
            o.total_amount.to_f.round(2),
            o.payment_status.capitalize,
            o.status_note.presence || "Awaiting payment / fulfillment confirmation"
          ]
        end

        B2bOrder.where(created_at: range, status: %w[pending pending_request pending_payment]).includes(:seller_dealer).order(created_at: :desc).find_each do |o|
          buyer_info = Reports::PrivacyFilter.buyer_reference(o, scope: :admin)
          seller     = o.seller_dealer ? "#{o.seller_dealer.full_name} [#{o.seller_dealer.dealer_code}]" : "Marketplace"

          rows << [
            o.reference_number,
            "B2B",
            o.created_at.strftime("%d %b %Y %H:%M"),
            buyer_info,
            seller,
            o.total_amount.to_f.round(2),
            o.payment_status.capitalize,
            o.status_note.presence || "Broadcast or payment link pending"
          ]
        end

        { title: "Admin Pending & Failed Orders Log", headers: headers, rows: rows }
      end
    end
  end
end
