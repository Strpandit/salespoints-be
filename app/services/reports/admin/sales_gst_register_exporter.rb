module Reports
  module Admin
    class SalesGstRegisterExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Invoice #", "Invoice Date", "Customer Reference", "Place of Supply", "Taxable Amount (₹)", "GST Rate (%)", "CGST (₹)", "SGST (₹)", "IGST (₹)", "Total Invoice Amount (₹)"]
        rows = []

        Order.where(created_at: range).where.not(status: "cancelled").includes(order_items: { product_variant: :product }).find_each do |o|
          inv_num = o.invoice_number.presence || "INV-#{o.order_number}"
          inv_dt  = o.placed_at&.strftime("%d %b %Y") || o.created_at.strftime("%d %b %Y")
          buyer   = Reports::PrivacyFilter.buyer_reference(o, scope: :admin)

          o.order_items.each do |item|
            rate  = item.product_variant&.product&.tax_rate.to_f
            gross = item.total_price.to_f
            tax   = gross * (rate / 100.0)

            rows << [
              inv_num,
              inv_dt,
              buyer,
              "India",
              gross.round(2),
              rate,
              (tax / 2.0).round(2),
              (tax / 2.0).round(2),
              0.0,
              (gross + tax).round(2)
            ]
          end
        end

        { title: "Admin Sales GST Register (GSTR-1 Compliant)", headers: headers, rows: rows }
      end
    end
  end
end
