module Reports
  module Admin
    class VendorPerformanceExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Dealer Code", "Dealer Business Name", "Phone", "Total Orders Received", "Delivered Orders", "Cancelled Orders", "Fulfillment Rate (%)", "Total Gross Sales (₹)"]
        rows = Dealer.includes(:dealer_profile).map do |d|
          d_code  = d.dealer_code
          b_name  = d.dealer_profile&.business_name || d.full_name
          orders  = Order.where(seller_dealer_id: d.id, created_at: range)
          tot_cnt = orders.count
          del_cnt = orders.where(status: "delivered").count
          can_cnt = orders.where(status: "cancelled").count
          rate    = tot_cnt.positive? ? ((del_cnt.to_f / tot_cnt) * 100).round(2) : 100.0
          sales   = orders.where.not(status: "cancelled").sum(:total_amount).to_f

          [d_code, b_name, d.phone || "N/A", tot_cnt, del_cnt, can_cnt, "#{rate}%", sales.round(2)]
        end

        { title: "Admin Vendor SLA & Fulfillment Performance Report", headers: headers, rows: rows }
      end
    end
  end
end
