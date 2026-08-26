module Reports
  module Admin
    class CustomerAnalyticsExporter < Reports::BaseExporter
      def generate
        headers = ["Customer ID", "Customer Name", "Phone", "Email", "Total Orders", "Lifetime Value (LTV) (₹)", "First Order Date", "Last Order Date"]
        rows = Account.all.map do |acc|
          orders   = Order.where(buyer_type: "Account", buyer_id: acc.id).where.not(status: "cancelled")
          tot_cnt  = orders.count
          ltv      = orders.sum(:total_amount).to_f
          first_dt = orders.minimum(:created_at)&.strftime("%d %b %Y") || "—"
          last_dt  = orders.maximum(:created_at)&.strftime("%d %b %Y") || "—"

          [acc.id, "#{acc.first_name} #{acc.last_name}", acc.phone || "N/A", acc.email || "N/A", tot_cnt, ltv.round(2), first_dt, last_dt]
        end

        { title: "Admin Customer LTV & Repeat Purchase Analytics", headers: headers, rows: rows }
      end
    end
  end
end
