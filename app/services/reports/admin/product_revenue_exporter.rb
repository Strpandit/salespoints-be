module Reports
  module Admin
    class ProductRevenueExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Product Name", "SKU", "Category", "Brand", "Units Sold", "Gross GMV Revenue (₹)", "Selling Price (₹)", "Dealer Price (₹)"]
        p_map = {}

        Order.where(created_at: range).where.not(status: "cancelled").includes(order_items: { product_variant: { product: [:category, :brand] } }).find_each do |o|
          o.order_items.each do |item|
            pv     = item.product_variant
            p_name = pv&.product&.name || "Product"
            sku    = pv&.variant_sku || "SKU"
            cat    = pv&.product&.category&.name || "Uncategorized"
            brand  = pv&.product&.brand&.name || "Generic"
            key    = "#{p_name} (#{sku})"

            p_map[key] ||= { name: p_name, sku: sku, cat: cat, brand: brand, qty: 0, gmv: 0.0, price: pv&.selling_price.to_f, d_price: pv&.dealer_price.to_f }
            p_map[key][:qty] += item.quantity.to_i
            p_map[key][:gmv] += item.total_price.to_f
          end
        end

        rows = p_map.values.map do |v|
          [v[:name], v[:sku], v[:cat], v[:brand], v[:qty], v[:gmv].round(2), v[:price].round(2), v[:d_price].round(2)]
        end

        { title: "Admin Product Revenue & Margin Report", headers: headers, rows: rows }
      end
    end
  end
end
