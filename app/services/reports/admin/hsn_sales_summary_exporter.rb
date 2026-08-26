module Reports
  module Admin
    class HsnSalesSummaryExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["HSN Code", "Units Sold", "Taxable Value (₹)", "CGST (₹)", "SGST (₹)", "Total Tax Value (₹)"]
        hsn_map = {}

        Order.where(created_at: range).where.not(status: "cancelled").includes(order_items: { product_variant: :product }).find_each do |o|
          o.order_items.each do |item|
            hsn = item.product_variant&.hsn_code.presence || item.product_variant&.product&.hsn_code.presence || "N/A"
            rate = item.product_variant&.product&.tax_rate.to_f
            gross = item.total_price.to_f
            tax   = gross * (rate / 100.0)

            hsn_map[hsn] ||= { qty: 0, taxable: 0.0, tax: 0.0 }
            hsn_map[hsn][:qty] += item.quantity.to_i
            hsn_map[hsn][:taxable] += gross
            hsn_map[hsn][:tax] += tax
          end
        end

        rows = hsn_map.map do |hsn, v|
          cgst = (v[:tax] / 2.0).round(2)
          sgst = (v[:tax] / 2.0).round(2)
          [hsn, v[:qty], v[:taxable].round(2), cgst, sgst, v[:tax].round(2)]
        end

        { title: "Admin HSN Sales Tax Summary Report", headers: headers, rows: rows }
      end
    end
  end
end
