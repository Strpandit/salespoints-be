module Reports
  module Admin
    class CreditNoteRegisterExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Credit Note ID", "Requester Type", "Reason / Notes", "Refund Amount (₹)", "Status", "Issued Date"]
        rows = ReturnRequest.where(created_at: range, request_type: "refund").order(created_at: :desc).map do |rr|
          [
            "CN-#{rr.id}",
            rr.requester_type,
            rr.reason.presence || rr.details.presence || "Sales Return",
            rr.refund_amount.to_f.round(2),
            rr.status.capitalize,
            rr.created_at.strftime("%d %b %Y")
          ]
        end

        { title: "Admin Credit Note Register (Sales Returns)", headers: headers, rows: rows }
      end
    end
  end
end
