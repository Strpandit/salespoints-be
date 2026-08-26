module Reports
  module Vendor
    class HsnSummaryExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["HSN Code", "Units Sold", "Taxable Value (₹)", "CGST (₹)", "SGST (₹)", "Total Tax (₹)"]
        hsn_map = {}

        Order.where(seller_dealer_id: dealer.id, created_at: range).includes(order_items: { product_variant: :product }).find_each do |o|
          o.order_items.each do |item|
            hsn = item.product_variant&.hsn_code.presence || item.product_variant&.product&.hsn_code.presence || "N/A"
            tax_rate = item.product_variant&.product&.tax_rate.to_f
            gross    = item.total_price.to_f
            tax_amt  = gross * (tax_rate / 100.0)

            hsn_map[hsn] ||= { qty: 0, taxable: 0.0, tax: 0.0 }
            hsn_map[hsn][:qty] += item.quantity.to_i
            hsn_map[hsn][:taxable] += gross
            hsn_map[hsn][:tax] += tax_amt
          end
        end

        rows = hsn_map.map do |hsn, v|
          cgst = (v[:tax] / 2.0).round(2)
          sgst = (v[:tax] / 2.0).round(2)
          [hsn, v[:qty], v[:taxable].round(2), cgst, sgst, v[:tax].round(2)]
        end

        { title: "Vendor HSN Summary Report", headers: headers, rows: rows }
      end
    end
  end
end
