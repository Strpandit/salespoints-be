module Reports
  module Admin
    class CategoryBrandSalesExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Category Name", "Brand Name", "Units Sold", "Total Revenue (₹)"]
        cat_brand_map = {}

        Order.where(created_at: range).where.not(status: "cancelled").includes(order_items: { product_variant: { product: [:category, :brand] } }).find_each do |o|
          o.order_items.each do |item|
            cat_name = item.product_variant&.product&.category&.name || "Uncategorized"
            b_name   = item.product_variant&.product&.brand&.name || "Generic"
            key      = "#{cat_name} | #{b_name}"

            cat_brand_map[key] ||= { category: cat_name, brand: b_name, qty: 0, total: 0.0 }
            cat_brand_map[key][:qty] += item.quantity.to_i
            cat_brand_map[key][:total] += item.total_price.to_f
          end
        end

        rows = cat_brand_map.values.map do |v|
          [v[:category], v[:brand], v[:qty], v[:total].round(2)]
        end

        { title: "Admin Category & Brand Sales Report", headers: headers, rows: rows }
      end
    end
  end
end
