module Reports
  module Admin
    class VendorInvoiceRegisterExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Invoice #", "Invoice Date", "Dealer Code", "Dealer Business Name", "Order #", "Taxable Value (₹)", "GST Rate (%)", "CGST (₹)", "SGST (₹)", "Total Invoice Amount (₹)"]
        rows = []

        Order.where(created_at: range).where.not(status: "cancelled").includes(:seller_dealer, order_items: { product_variant: :product }).find_each do |o|
          next unless o.seller_dealer
          inv_num = o.invoice_number.presence || "INV-V-#{o.order_number}"
          inv_dt  = o.created_at.strftime("%d %b %Y")
          d_code  = o.seller_dealer.dealer_code
          d_biz   = o.seller_dealer.dealer_profile&.business_name || o.seller_dealer.full_name

          o.order_items.each do |item|
            rate  = item.product_variant&.product&.tax_rate.to_f
            gross = item.total_price.to_f
            tax   = gross * (rate / 100.0)

            rows << [
              inv_num,
              inv_dt,
              d_code,
              d_biz,
              o.order_number,
              gross.round(2),
              rate,
              (tax / 2.0).round(2),
              (tax / 2.0).round(2),
              (gross + tax).round(2)
            ]
          end
        end

        { title: "Admin Vendor Tax Invoice Register", headers: headers, rows: rows }
      end
    end
  end
end
