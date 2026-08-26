module Reports
  module Vendor
    class PayoutDetailsExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Order #", "Order Date", "Order GMV (₹)", "Commission Rate (%)", "Commission Fee (₹)", "Net Settlement Payable (₹)", "Settlement Status", "Settled Date"]
        rows = Order.where(seller_dealer_id: dealer.id, created_at: range).order(created_at: :desc).map do |o|
          [o.order_number, o.created_at.strftime("%d %b %Y"), o.total_amount.to_f.round(2), o.commission_rate.to_f, o.commission_amount.to_f.round(2), o.seller_settlement_amount.to_f.round(2), o.settlement_status.capitalize, o.settled_at&.strftime("%d %b %Y") || "Pending"]
        end

        { title: "Vendor Payout Detailed Breakup Report", headers: headers, rows: rows }
      end
    end
  end
end
