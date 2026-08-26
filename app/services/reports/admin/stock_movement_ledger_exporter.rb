module Reports
  module Admin
    class StockMovementLedgerExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Order / Reference #", "Movement Date", "Dealer Code", "Product Name", "SKU", "Movement Qty", "Movement Type"]
        rows = []

        Order.where(created_at: range).where.not(status: "cancelled").includes(:seller_dealer, order_items: { product_variant: :product }).find_each do |o|
          d_code = o.seller_dealer&.dealer_code || "Marketplace"

          o.order_items.each do |item|
            p_name = item.product_variant&.product&.name || "Product"
            sku    = item.product_variant&.variant_sku || "SKU"

            rows << [
              o.order_number,
              o.created_at.strftime("%d %b %Y %H:%M"),
              d_code,
              p_name,
              sku,
              "-#{item.quantity}",
              "Sales Outflow"
            ]
          end
        end

        { title: "Admin Stock Movement Audit Ledger", headers: headers, rows: rows }
      end
    end
  end
end
