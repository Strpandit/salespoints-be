module Reports
  module Admin
    class ProductWiseSalesExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Product Name", "SKU", "Category", "Brand", "Units Sold", "Total GMV Revenue (₹)"]
        product_map = {}

        Order.where(created_at: range).where.not(status: "cancelled").includes(order_items: { product_variant: { product: [:category, :brand] } }).find_each do |o|
          o.order_items.each do |item|
            p_name   = item.product_variant&.product&.name || "Product"
            v_sku    = item.product_variant&.variant_sku || "SKU"
            cat_name = item.product_variant&.product&.category&.name || "Uncategorized"
            b_name   = item.product_variant&.product&.brand&.name || "Generic"
            key      = "#{p_name} (SKU: #{v_sku})"

            product_map[key] ||= { name: p_name, sku: v_sku, category: cat_name, brand: b_name, qty: 0, total: 0.0 }
            product_map[key][:qty] += item.quantity.to_i
            product_map[key][:total] += item.total_price.to_f
          end
        end

        rows = product_map.values.map do |v|
          [v[:name], v[:sku], v[:category], v[:brand], v[:qty], v[:total].round(2)]
        end

        { title: "Admin Product-wise Sales Report", headers: headers, rows: rows }
      end
    end
  end
end
