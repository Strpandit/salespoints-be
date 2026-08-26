module Reports
  module Admin
    class VendorWisePurchasesExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Dealer Code", "Dealer Business Name", "Orders Count", "Total Purchase Value (₹)", "Commission Deducted (₹)", "Net Payable Amount (₹)"]
        v_map = {}

        Order.where(created_at: range).where.not(status: "cancelled").includes(:seller_dealer).find_each do |o|
          next unless o.seller_dealer
          d_code = o.seller_dealer.dealer_code
          b_name = o.seller_dealer.dealer_profile&.business_name || o.seller_dealer.full_name

          v_map[d_code] ||= { code: d_code, name: b_name, orders: 0, purchase: 0.0, comm: 0.0, net: 0.0 }
          v_map[d_code][:orders] += 1
          v_map[d_code][:purchase] += o.total_amount.to_f
          v_map[d_code][:comm] += o.commission_amount.to_f
          v_map[d_code][:net] += o.seller_settlement_amount.to_f
        end

        rows = v_map.values.map do |v|
          [v[:code], v[:name], v[:orders], v[:purchase].round(2), v[:comm].round(2), v[:net].round(2)]
        end

        { title: "Admin Vendor-wise Purchase Volume Report", headers: headers, rows: rows }
      end
    end
  end
end
