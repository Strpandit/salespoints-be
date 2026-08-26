module Reports
  module Admin
    class RevenueSummaryExporter < Reports::BaseExporter
      def generate
        range = date_range

        b2c = Order.where(created_at: range).where.not(status: "cancelled")
        b2b = B2bOrder.where(created_at: range).where.not(status: %w[cancelled rejected_request])

        daily_map = {}

        b2c.find_each do |o|
          dt = o.created_at.to_date.to_s
          daily_map[dt] ||= { b2c: 0.0, b2b: 0.0, comm: 0.0 }
          daily_map[dt][:b2c] += o.total_amount.to_f
          daily_map[dt][:comm] += o.commission_amount.to_f
        end

        b2b.find_each do |o|
          dt = o.created_at.to_date.to_s
          daily_map[dt] ||= { b2c: 0.0, b2b: 0.0, comm: 0.0 }
          daily_map[dt][:b2b] += o.total_amount.to_f
        end

        headers = ["Date", "B2C Sales GMV (₹)", "B2B Sales GMV (₹)", "Total Marketplace GMV (₹)", "Marketplace Commission Earned (₹)"]
        rows = daily_map.sort.map do |dt, val|
          tot_gmv = val[:b2c] + val[:b2b]
          [Date.parse(dt).strftime("%d %b %Y"), val[:b2c].round(2), val[:b2b].round(2), tot_gmv.round(2), val[:comm].round(2)]
        end

        { title: "Admin Daily Revenue Summary Report", headers: headers, rows: rows }
      end
    end
  end
end
