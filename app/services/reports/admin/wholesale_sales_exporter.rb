module Reports
  module Admin
    class WholesaleSalesExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Post ID", "Wholesaler Dealer Code", "Business Name", "Item Title", "Model No", "Unit Price (₹)", "Stock Qty", "Approval Status", "Created Date"]
        rows = WholesalerPost.where(created_at: range).includes(dealer: :dealer_profile).order(created_at: :desc).map do |wp|
          d_code = wp.dealer&.dealer_code || "N/A"
          b_name = wp.dealer&.dealer_profile&.business_name || wp.dealer&.full_name || "Wholesaler"

          [
            wp.id,
            d_code,
            b_name,
            wp.title.presence || "Wholesale Post",
            wp.modal_no.presence || "N/A",
            wp.price.to_f.round(2),
            wp.stock_quantity.to_i,
            wp.approve_status.capitalize,
            wp.created_at.strftime("%d %b %Y")
          ]
        end

        { title: "Admin Wholesale Sales & Posts Register", headers: headers, rows: rows }
      end
    end
  end
end
