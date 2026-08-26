module Reports
  module Vendor
    class ProductRevenueExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Product Name", "SKU", "Units Sold", "Total Sales Revenue (₹)"]
        revenue_map = {}

        Order.where(seller_dealer_id: dealer.id, created_at: range).includes(order_items: { product_variant: :product }).find_each do |o|
          o.order_items.each do |item|
            name = item.product_variant&.product&.name || "Product"
            sku  = item.product_variant&.variant_sku || "SKU"
            key  = "#{name} (SKU: #{sku})"
            revenue_map[key] ||= { qty: 0, total: 0.0 }
            revenue_map[key][:qty] += item.quantity.to_i
            revenue_map[key][:total] += item.total_price.to_f
          end
        end

        rows = revenue_map.map do |k, v|
          parts = k.split(" (SKU: ")
          p_name = parts[0]
          sku = parts[1]&.chomp(")")
          [p_name, sku, v[:qty], v[:total].round(2)]
        end

        { title: "Vendor Product Revenue Report", headers: headers, rows: rows }
      end
    end
  end
end
