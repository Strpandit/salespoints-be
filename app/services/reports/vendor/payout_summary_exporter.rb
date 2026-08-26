module Reports
  module Vendor
    class PayoutSummaryExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Payout Request #", "Amount (₹)", "Status", "Bank Account", "Payment Mode", "Reference / UTR", "Requested At", "Paid At"]
        rows = DealerPayout.where(dealer_id: dealer.id, created_at: range).order(created_at: :desc).map do |p|
          bank_acc = p.bank_account_number.present? ? "•••• #{p.bank_account_number.last(4)}" : "N/A"
          [p.request_number, p.amount.to_f.round(2), p.status.capitalize, bank_acc, p.payment_mode || "N/A", p.payment_reference || "N/A", p.created_at.strftime("%d %b %Y"), p.paid_at&.strftime("%d %b %Y %H:%M") || "—"]
        end

        { title: "Vendor Payout Summary Report", headers: headers, rows: rows }
      end
    end
  end
end
