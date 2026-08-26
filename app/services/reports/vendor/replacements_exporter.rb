module Reports
  module Vendor
    class ReplacementsExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Request ID", "Request Type", "Defective Quantity", "Replacement Mode", "Refund / Value Impact (₹)", "Status", "Requested At"]
        rows = ReturnRequest.where(requester_id: dealer.id, created_at: range).order(created_at: :desc).map do |r|
          [r.id, r.request_type.capitalize, r.defective_quantity, r.replacement_mode.capitalize, r.refund_amount.to_f.round(2), r.status.capitalize, r.created_at.strftime("%d %b %Y")]
        end

        { title: "Vendor Replacements & Returns Impact Report", headers: headers, rows: rows }
      end
    end
  end
end
