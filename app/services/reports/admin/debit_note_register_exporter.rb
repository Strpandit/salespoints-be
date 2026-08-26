module Reports
  module Admin
    class DebitNoteRegisterExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Debit Note ID", "Dealer / Vendor Code", "Adjustment Reason", "Amount (₹)", "Status", "Issued Date"]
        rows = ReturnRequest.where(created_at: range, request_type: "replacement").order(created_at: :desc).map do |rr|
          dealer_code = rr.requester_type == "Dealer" ? (Dealer.find_by(id: rr.requester_id)&.dealer_code || "Dealer") : "Vendor"
          [
            "DN-#{rr.id}",
            dealer_code,
            rr.reason.presence || "Defective Item Penalty / Adjustment",
            rr.seller_adjustment_amount.to_f.round(2),
            rr.status.capitalize,
            rr.created_at.strftime("%d %b %Y")
          ]
        end

        { title: "Admin Debit Note Register (Vendor Penalties & Adjustments)", headers: headers, rows: rows }
      end
    end
  end
end
