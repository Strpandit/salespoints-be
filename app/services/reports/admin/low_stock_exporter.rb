module Reports
  module Admin
    class LowStockExporter < Reports::BaseExporter
      def generate
        headers = ["Dealer Code", "Dealer Business Name", "Product Name", "Variant SKU", "Current Stock Qty", "Reorder Alert Status"]
        rows = []

        DealerProduct.where("stock_quantity <= 10").includes(:dealer, product_variant: :product).find_each do |dp|
          d_code = dp.dealer&.dealer_code || "N/A"
          b_name = dp.dealer&.dealer_profile&.business_name || dp.dealer&.full_name || "Dealer"
          p_name = dp.product_variant&.product&.name || "Product"
          sku    = dp.product_variant&.variant_sku || "SKU"
          qty    = dp.stock_quantity.to_i
          status = qty == 0 ? "Out of Stock (CRITICAL)" : "Low Stock (Reorder Recommended)"

          rows << [d_code, b_name, p_name, sku, qty, status]
        end

        { title: "Admin Low Stock & Reorder Alert Report", headers: headers, rows: rows }
      end
    end
  end
end
