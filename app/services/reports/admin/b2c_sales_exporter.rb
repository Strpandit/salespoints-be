module Reports
  module Admin
    class B2cSalesExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Order #", "Order Date", "Customer Name", "Customer Phone", "Customer Email", "Seller Dealer", "Items Qty", "Subtotal (₹)", "Tax (₹)", "Total Amount (₹)", "Payment Mode", "Payment Status", "Status"]
        rows = Order.where(created_at: range, buyer_type: "Account").order(created_at: :desc).map do |o|
          account = Account.find_by(id: o.buyer_id)
          c_name  = account ? [account.first_name, account.last_name].compact.join(" ") : "B2C Customer"
          c_phone = account&.phone || "N/A"
          c_email = account&.email || "N/A"
          seller  = o.seller_dealer ? "#{o.seller_dealer.full_name} [#{o.seller_dealer.dealer_code}]" : "Marketplace"
          pay_mode = Reports::PrivacyFilter.format_payment_method(o.payment_method)

          [
            o.order_number,
            o.created_at.strftime("%d %b %Y %H:%M"),
            c_name,
            c_phone,
            c_email,
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

        { title: "Admin B2C Sales Register", headers: headers, rows: rows }
      end
    end
  end
end
