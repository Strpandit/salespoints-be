module Reports
  module Admin
    class VendorPayableSummaryExporter < Reports::BaseExporter
      def generate
        headers = ["Dealer Code", "Dealer Business Name", "Phone", "Settlement Balance (₹)", "Pending Payout Requests (₹)", "Total Accounts Payable (₹)"]
        rows = Dealer.includes(:dealer_profile).map do |d|
          d_code  = d.dealer_code
          b_name  = d.dealer_profile&.business_name || d.full_name
          balance = d.settlement_balance.to_f
          pending = DealerPayout.where(dealer_id: d.id, status: "pending").sum(:amount).to_f
          total   = balance + pending

          [d_code, b_name, d.phone || "N/A", balance.round(2), pending.round(2), total.round(2)]
        end

        { title: "Admin Vendor Payable & Settlement Balance Summary", headers: headers, rows: rows }
      end
    end
  end
end
