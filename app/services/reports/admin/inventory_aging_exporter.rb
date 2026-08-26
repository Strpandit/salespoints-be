module Reports
  module Admin
    class InventoryAgingExporter < Reports::BaseExporter
      def generate
        headers = ["Dealer Code", "Product Name", "SKU", "Current Stock", "Age (Days)", "Aging Bracket"]
        rows = []

        DealerProduct.includes(:dealer, product_variant: :product).find_each do |dp|
          d_code = dp.dealer&.dealer_code || "N/A"
          p_name = dp.product_variant&.product&.name || "Product"
          sku    = dp.product_variant&.variant_sku || "SKU"
          stock  = dp.stock_quantity.to_i
          days   = (Time.current - dp.created_at) / 1.day
          bracket = days > 90 ? "90+ Days (Aged)" : (days > 30 ? "31-90 Days (Moderate)" : "0-30 Days (Fresh)")

          rows << [d_code, p_name, sku, stock, days.to_i, bracket]
        end

        { title: "Admin Inventory Aging Analysis Report", headers: headers, rows: rows }
      end
    end
  end
end
