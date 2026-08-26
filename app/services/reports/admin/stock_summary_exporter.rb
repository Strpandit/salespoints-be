module Reports
  module Admin
    class StockSummaryExporter < Reports::BaseExporter
      def generate
        headers = ["Product Name", "Variant SKU", "Category", "Brand", "Active Vendors Count", "Total Global Stock Qty"]
        p_map = {}

        DealerProduct.includes(product_variant: { product: [:category, :brand] }).find_each do |dp|
          pv     = dp.product_variant
          p_name = pv&.product&.name || "Product"
          sku    = pv&.variant_sku || "SKU"
          cat    = pv&.product&.category&.name || "Uncategorized"
          brand  = pv&.product&.brand&.name || "Generic"
          key    = "#{p_name} (#{sku})"

          p_map[key] ||= { name: p_name, sku: sku, cat: cat, brand: brand, vendors: 0, stock: 0 }
          p_map[key][:vendors] += 1
          p_map[key][:stock] += dp.stock_quantity.to_i
        end

        rows = p_map.values.map do |v|
          [v[:name], v[:sku], v[:cat], v[:brand], v[:vendors], v[:stock]]
        end

        { title: "Admin Global Stock Summary Snapshot", headers: headers, rows: rows }
      end
    end
  end
end
