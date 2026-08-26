module Reports
  module Admin
    class VendorRevenueExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Dealer Code", "Dealer Business Name", "Dealer Phone", "Total Orders", "Gross GMV Sales (₹)", "Marketplace Commission (₹)", "Net Settlement Amount (₹)"]
        v_map = {}

        Order.where(created_at: range).where.not(status: "cancelled").includes(:seller_dealer).find_each do |o|
          next unless o.seller_dealer
          d = o.seller_dealer
          d_code = d.dealer_code
          b_name = d.dealer_profile&.business_name || d.full_name

          v_map[d_code] ||= { code: d_code, name: b_name, phone: d.phone || "N/A", orders: 0, gmv: 0.0, comm: 0.0, net: 0.0 }
          v_map[d_code][:orders] += 1
          v_map[d_code][:gmv] += o.total_amount.to_f
          v_map[d_code][:comm] += o.commission_amount.to_f
          v_map[d_code][:net] += o.seller_settlement_amount.to_f
        end

        rows = v_map.values.map do |v|
          [v[:code], v[:name], v[:phone], v[:orders], v[:gmv].round(2), v[:comm].round(2), v[:net].round(2)]
        end

        { title: "Admin Vendor Revenue & Settlement Summary Report", headers: headers, rows: rows }
      end
    end
  end
end
