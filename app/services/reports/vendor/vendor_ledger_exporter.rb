module Reports
  module Vendor
    class VendorLedgerExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Reference Code", "Entry Type", "Direction (Dr/Cr)", "Amount (₹)", "Balance After (₹)", "Description", "Transaction Date"]
        rows = DealerLedgerEntry.where(dealer_id: dealer.id, created_at: range).order(created_at: :desc).map do |le|
          [le.reference_code, le.entry_type.titleize, le.direction.upcase, le.amount.to_f.round(2), le.balance_after.to_f.round(2), le.description, le.created_at.strftime("%d %b %Y %H:%M")]
        end

        { title: "Vendor Ledger Running Statement", headers: headers, rows: rows }
      end
    end
  end
end
