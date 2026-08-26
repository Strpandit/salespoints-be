module Reports
  module Vendor
    class WholesaleSalesExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Post ID", "Wholesale Item", "Quantity Sold", "Price (₹)", "Buyer Reference", "Status", "Date"]
        rows = WholesalerPost.where(dealer_id: dealer.id, created_at: range).order(created_at: :desc).map do |wp|
          buyer_ref = "Dealer Code Only"
          [wp.id, wp.title || wp.modal_no, wp.stock_quantity, wp.price.to_f.round(2), buyer_ref, wp.approve_status.capitalize, wp.created_at.strftime("%d %b %Y")]
        end

        { title: "Vendor Wholesale Sales Report", headers: headers, rows: rows }
      end
    end
  end
end
