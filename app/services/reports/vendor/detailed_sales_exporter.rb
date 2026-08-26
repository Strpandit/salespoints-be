module Reports
  module Vendor
    class DetailedSalesExporter < Reports::BaseExporter
      def generate
        dealer = current_user
        range  = date_range

        headers = ["Order Reference", "Channel", "Order Date", "Buyer Reference", "Product / Variant", "Quantity", "Unit Price (₹)", "Gross Value (₹)", "Discount (₹)", "Taxable Value (₹)", "GST Rate (%)", "CGST (₹)", "SGST (₹)", "IGST (₹)", "Total Invoice Value (₹)", "Payment Mode"]
        rows = []

        Order.where(seller_dealer_id: dealer.id, created_at: range).includes(order_items: { product_variant: :product }).find_each do |o|
          buyer_ref = Reports::PrivacyFilter.buyer_reference(o, scope: :vendor)
          pay_mode  = Reports::PrivacyFilter.format_payment_method(o.payment_method)

          o.order_items.each do |item|
            p_name = item.product_variant&.product&.name || "Product"
            v_sku  = item.product_variant&.variant_sku || "SKU"
            qty    = item.quantity.to_i
            u_price = item.unit_price.to_f
            gross  = u_price * qty
            tax_rate = item.product_variant&.product&.tax_rate.to_f
            gst_amt = gross * (tax_rate / 100.0)

            rows << [
              o.order_number,
              "B2C",
              o.created_at.strftime("%d %b %Y"),
              buyer_ref,
              "#{p_name} (#{v_sku})",
              qty,
              u_price.round(2),
              gross.round(2),
              0.0,
              gross.round(2),
              tax_rate,
              (gst_amt / 2.0).round(2),
              (gst_amt / 2.0).round(2),
              0.0,
              (gross + gst_amt).round(2),
              pay_mode
            ]
          end
        end

        B2bOrder.where(seller_dealer_id: dealer.id, created_at: range).includes(b2b_order_items: { product_variant: :product }).find_each do |o|
          buyer_ref = Reports::PrivacyFilter.buyer_reference(o, scope: :vendor)
          pay_mode  = Reports::PrivacyFilter.format_payment_method(o.payment_method)

          o.b2b_order_items.each do |item|
            p_name = item.product_variant&.product&.name || "Product"
            v_sku  = item.product_variant&.variant_sku || "SKU"
            qty    = item.quantity.to_i
            u_price = item.unit_price.to_f
            gross  = u_price * qty

            rows << [
              o.reference_number,
              "B2B",
              o.created_at.strftime("%d %b %Y"),
              buyer_ref,
              "#{p_name} (#{v_sku})",
              qty,
              u_price.round(2),
              gross.round(2),
              0.0,
              gross.round(2),
              0.0,
              0.0,
              0.0,
              0.0,
              gross.round(2),
              pay_mode
            ]
          end
        end

        {
          title: "Vendor Detailed Sales Report",
          headers: headers,
          rows: rows
        }
      end
    end
  end
end
