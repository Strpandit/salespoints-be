module Reports
  module Admin
    class PrepaidCodRegisterExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Order Number", "Channel", "Buyer Details", "Seller Dealer", "Payment Mode", "Total Amount (₹)", "Payment Status", "Order Status", "Placed At"]
        rows = []

        Order.where(created_at: range).order(created_at: :desc).find_each do |o|
          buyer_info = Reports::PrivacyFilter.buyer_reference(o, scope: :admin)
          seller     = o.seller_dealer ? "#{o.seller_dealer.first_name} #{o.seller_dealer.last_name} [#{o.seller_dealer.dealer_code}]" : "Marketplace"
          pay_mode   = Reports::PrivacyFilter.format_payment_method(o.payment_method)

          rows << [
            o.order_number,
            "B2C",
            buyer_info,
            seller,
            pay_mode,
            o.total_amount.to_f.round(2),
            o.payment_status.capitalize,
            o.status.capitalize,
            o.created_at.strftime("%d %b %Y %H:%M")
          ]
        end

        B2bOrder.where(created_at: range).order(created_at: :desc).find_each do |o|
          buyer_info = Reports::PrivacyFilter.buyer_reference(o, scope: :admin)
          seller     = o.seller_dealer ? "#{o.seller_dealer.first_name} #{o.seller_dealer.last_name} [#{o.seller_dealer.dealer_code}]" : "Marketplace"
          pay_mode   = Reports::PrivacyFilter.format_payment_method(o.payment_method)

          rows << [
            o.reference_number,
            "B2B",
            buyer_info,
            seller,
            pay_mode,
            o.total_amount.to_f.round(2),
            o.payment_status.capitalize,
            o.status.capitalize,
            o.created_at.strftime("%d %b %Y %H:%M")
          ]
        end

        {
          title: "Admin Prepaid vs Postpaid Sales Register",
          headers: headers,
          rows: rows
        }
      end
    end
  end
end
