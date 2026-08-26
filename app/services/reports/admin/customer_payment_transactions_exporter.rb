module Reports
  module Admin
    class CustomerPaymentTransactionsExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Attempt #", "Buyer Type", "Buyer Name", "Payment Gateway", "Gateway Ref #", "Amount (₹)", "Status", "Attempt Date"]
        rows = PaymentAttempt.where(created_at: range).order(created_at: :desc).map do |pa|
          buyer_name = if pa.buyer_type == "Account"
            acc = Account.find_by(id: pa.buyer_id)
            acc ? "#{acc.first_name} #{acc.last_name}" : "Customer"
          else
            d = Dealer.find_by(id: pa.buyer_id)
            d ? "#{d.full_name} [#{d.dealer_code}]" : "Dealer"
          end

          [
            pa.attempt_number,
            pa.buyer_type,
            buyer_name,
            pa.payment_gateway.to_s.titleize,
            pa.gateway_order_reference.presence || pa.payment_reference.presence || "N/A",
            pa.amount.to_f.round(2),
            pa.status.capitalize,
            pa.created_at.strftime("%d %b %Y %H:%M")
          ]
        end

        { title: "Admin Customer Payment Transactions Register", headers: headers, rows: rows }
      end
    end
  end
end
