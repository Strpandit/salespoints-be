module Reports
  module Admin
    class DealerPurchaseRegisterExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Purchase Invoice #", "Dealer Code", "Dealer Business Name", "Order #", "Gross Purchase Value (₹)", "Commission Deduction (₹)", "Net Payable Amount (₹)", "Purchase Date"]
        rows = Order.where(created_at: range).includes(:seller_dealer).find_each do |o|
          next unless o.seller_dealer
          inv_num = o.invoice_number.presence || "PUR-#{o.order_number}"
          d_code  = o.seller_dealer.dealer_code
          b_name  = o.seller_dealer.dealer_profile&.business_name || o.seller_dealer.full_name

          rows << [
            inv_num,
            d_code,
            b_name,
            o.order_number,
            o.total_amount.to_f.round(2),
            o.commission_amount.to_f.round(2),
            o.seller_settlement_amount.to_f.round(2),
            o.created_at.strftime("%d %b %Y")
          ]
        end

        { title: "Admin Dealer Purchase Register (Salespoints Purchases from Dealers)", headers: headers, rows: rows }
      end
    end
  end
end
