module Reports
  module Vendor
    class ProductPerformanceExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Product Name", "SKU", "Units Sold", "Total Sales (₹)", "Current Stock"]
        perf_map = {}

        DealerProduct.where(dealer_id: dealer.id).includes(product_variant: :product).each do |dp|
          p_name = dp.product_variant&.product&.name || "Product"
          sku    = dp.product_variant&.variant_sku || "SKU"
          perf_map[dp.product_variant_id] = { name: p_name, sku: sku, stock: dp.stock_quantity.to_i, qty: 0, total: 0.0 }
        end

        Order.where(seller_dealer_id: dealer.id, created_at: range).includes(:order_items).find_each do |o|
          o.order_items.each do |item|
            if perf_map[item.product_variant_id]
              perf_map[item.product_variant_id][:qty] += item.quantity.to_i
              perf_map[item.product_variant_id][:total] += item.total_price.to_f
            end
          end
        end

        rows = perf_map.values.map do |v|
          [v[:name], v[:sku], v[:qty], v[:total].round(2), v[:stock]]
        end

        { title: "Vendor Product Performance Report", headers: headers, rows: rows }
      end
    end
  end
end
