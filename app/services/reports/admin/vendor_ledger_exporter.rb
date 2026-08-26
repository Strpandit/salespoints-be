module Reports
  module Admin
    class VendorLedgerExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Dealer Code", "Dealer Business Name", "Reference Code", "Entry Type", "Direction (Dr/Cr)", "Amount (₹)", "Balance After (₹)", "Description", "Date"]
        rows = DealerLedgerEntry.where(created_at: range).includes(dealer: :dealer_profile).order(created_at: :desc).map do |le|
          d_code = le.dealer&.dealer_code || "N/A"
          b_name = le.dealer&.dealer_profile&.business_name || le.dealer&.full_name || "Dealer"

          [
            d_code,
            b_name,
            le.reference_code,
            le.entry_type.titleize,
            le.direction.upcase,
            le.amount.to_f.round(2),
            le.balance_after.to_f.round(2),
            le.description,
            le.created_at.strftime("%d %b %Y %H:%M")
          ]
        end

        { title: "Admin Vendor Master Ledger Register", headers: headers, rows: rows }
      end
    end
  end
end
