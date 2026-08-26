module Reports
  module Vendor
    class StockReportExporter < Reports::BaseExporter
      def generate
        dealer = current_user

        headers = ["Product Name", "Variant SKU", "B2C Enabled", "B2B Enabled", "Current Stock Quantity", "Stock Status"]
        rows = DealerProduct.where(dealer_id: dealer.id).includes(product_variant: :product).map do |dp|
          p_name = dp.product_variant&.product&.name || "Product"
          v_sku  = dp.product_variant&.variant_sku || "SKU"
          stock  = dp.stock_quantity.to_i
          status = stock == 0 ? "Out of Stock" : (stock <= 10 ? "Low Stock" : "In Stock")

          [p_name, v_sku, dp.sell_in_b2c ? "Yes" : "No", dp.sell_in_b2b ? "Yes" : "No", stock, status]
        end

        { title: "Vendor Current Stock & Inventory Report", headers: headers, rows: rows }
      end
    end
  end
end
