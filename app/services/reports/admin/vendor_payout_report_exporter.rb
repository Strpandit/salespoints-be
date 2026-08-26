module Reports
  module Admin
    class VendorPayoutReportExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Payout Request #", "Dealer Code", "Dealer Business Name", "Amount (₹)", "Status", "Bank Name", "Account Number", "IFSC", "Payment Mode", "UTR / Ref #", "Requested At", "Paid At"]
        rows = DealerPayout.where(created_at: range).includes(dealer: :dealer_profile).order(created_at: :desc).map do |p|
          d_code = p.dealer&.dealer_code || "N/A"
          b_name = p.dealer&.dealer_profile&.business_name || p.dealer&.full_name || "Dealer"
          bank_acc = p.bank_account_number.present? ? "•••• #{p.bank_account_number.last(4)}" : "N/A"

          [
            p.request_number,
            d_code,
            b_name,
            p.amount.to_f.round(2),
            p.status.capitalize,
            p.bank_name.presence || "N/A",
            bank_acc,
            p.ifsc_code.presence || "N/A",
            p.payment_mode.presence || "N/A",
            p.payment_reference.presence || "N/A",
            p.created_at.strftime("%d %b %Y"),
            p.paid_at&.strftime("%d %b %Y %H:%M") || "—"
          ]
        end

        { title: "Admin Vendor Bank Payout Transfer Register", headers: headers, rows: rows }
      end
    end
  end
end
