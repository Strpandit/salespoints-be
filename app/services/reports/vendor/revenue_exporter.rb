module Reports
  module Vendor
    class RevenueExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        b2c = Order.where(seller_dealer_id: dealer.id, created_at: range).where.not(status: "cancelled")
        b2b = B2bOrder.where(seller_dealer_id: dealer.id, created_at: range).where.not(status: %w[cancelled rejected_request])

        combined = {}
        b2c.each { |o| dt = o.created_at.to_date.to_s; combined[dt] = (combined[dt] || 0) + o.total_amount.to_f }
        b2b.each { |o| dt = o.created_at.to_date.to_s; combined[dt] = (combined[dt] || 0) + o.total_amount.to_f }

        headers = ["Date", "Daily Net Revenue (₹)"]
        rows = combined.sort.map { |dt, val| [Date.parse(dt).strftime("%d %b %Y"), val.round(2)] }

        { title: "Vendor Revenue Report", headers: headers, rows: rows }
      end
    end
  end
end
