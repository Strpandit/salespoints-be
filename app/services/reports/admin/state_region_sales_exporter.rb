module Reports
  module Admin
    class StateRegionSalesExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Shipping State", "Pincode / City", "Total Orders", "Total Revenue (₹)"]
        region_map = {}

        Order.where(created_at: range).where.not(status: "cancelled").find_each do |o|
          addr  = o.shipping_address || {}
          state = addr["state"].presence || "India"
          city  = addr["city"].presence || addr["postal_code"].presence || "General"
          key   = "#{state} - #{city}"

          region_map[key] ||= { state: state, city: city, orders: 0, total: 0.0 }
          region_map[key][:orders] += 1
          region_map[key][:total] += o.total_amount.to_f
        end

        rows = region_map.values.map do |v|
          [v[:state], v[:city], v[:orders], v[:total].round(2)]
        end

        { title: "Admin State & Region Sales Report", headers: headers, rows: rows }
      end
    end
  end
end
