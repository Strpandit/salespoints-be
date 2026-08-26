module Reports
  module Vendor
    class CategoryRevenueExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Category Name", "Units Sold", "Total Revenue (₹)"]
        cat_map = {}

        Order.where(seller_dealer_id: dealer.id, created_at: range).includes(order_items: { product_variant: { product: :category } }).find_each do |o|
          o.order_items.each do |item|
            cat_name = item.product_variant&.product&.category&.name || "Uncategorized"
            cat_map[cat_name] ||= { qty: 0, total: 0.0 }
            cat_map[cat_name][:qty] += item.quantity.to_i
            cat_map[cat_name][:total] += item.total_price.to_f
          end
        end

        rows = cat_map.map { |cat, v| [cat, v[:qty], v[:total].round(2)] }

        { title: "Vendor Category Revenue Report", headers: headers, rows: rows }
      end
    end
  end
end
