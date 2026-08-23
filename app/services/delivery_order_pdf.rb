require 'prawn'
require 'prawn/table'

class DeliveryOrderPdf
  attr_reader :order

  def initialize(order)
    @order = order
  end

  def generate
    pdf = Prawn::Document.new(
      page_size: "A4",
      margin: 20,
      info: { Title: "Delivery Order #{order_reference}" }
    )

    setup_fonts(pdf)
    add_company_header(pdf)
    add_document_banner(pdf)
    add_seller_greeting(pdf)
    add_order_details_table(pdf)
    add_disbursement_breakup_table(pdf)
    add_shipping_address_box(pdf)
    add_terms_and_conditions(pdf)
    add_footer(pdf)

    pdf.render
  end

  private

  def setup_fonts(pdf)
    dejavu_normal = Rails.root.join("app/assets/fonts/DejaVuSans.ttf")
    if File.exist?(dejavu_normal)
      pdf.font_families.update(
        "DejaVu" => {
          normal: dejavu_normal,
          bold: Rails.root.join("app/assets/fonts/DejaVuSans-Bold.ttf"),
          italic: Rails.root.join("app/assets/fonts/DejaVuSans-Oblique.ttf"),
          bold_italic: Rails.root.join("app/assets/fonts/DejaVuSans-BoldOblique.ttf")
        }
      )
      pdf.font "DejaVu"
    else
      pdf.font "Helvetica"
    end
    pdf.font_size 9
  end

  def add_company_header(pdf)
    logo_path = Rails.root.join("app/assets/images/logo.png")

    pdf.bounding_box([0, pdf.cursor], width: pdf.bounds.width) do
      if File.exist?(logo_path)
        pdf.image logo_path, width: 130, position: :left
      else
        pdf.text "SALESPOINTS", size: 16, style: :bold, color: "1E3A8A"
      end

      pdf.move_cursor_to pdf.bounds.top if File.exist?(logo_path)

      header_text = <<~TEXT
        <b>SALESPOINTS INDIA PRIVATE LIMITED</b>
        Reg. Off: Prop No-49, Kh No. 70, Road Sadatpur, Karawal Nagar, New Delhi - 110094
        support.salespoints.in@gmail.com | +91-8368835228 | www.salespoints.in
        GSTIN - 07ABTCS6593H1ZH | CIN - U46524DC2026PTC471107
      TEXT

      pdf.text_box header_text,
                   at: [150, pdf.bounds.top],
                   width: pdf.bounds.width - 150,
                   size: 8,
                   inline_format: true,
                   align: :right
    end

    pdf.move_down 45
    pdf.stroke_horizontal_rule
    pdf.move_down 10
  end

  def add_document_banner(pdf)
    pdf.bounding_box([0, pdf.cursor], width: pdf.bounds.width, height: 24) do
      pdf.fill_color "0047AB"
      pdf.fill_rectangle [0, pdf.bounds.height], pdf.bounds.width, pdf.bounds.height
      pdf.fill_color "FFFFFF"
      pdf.text_box "DELIVERY ORDER / FULFILLMENT ORDER",
                   at: [0, pdf.bounds.height - 6],
                   width: pdf.bounds.width,
                   align: :center,
                   style: :bold,
                   size: 11
    end
    pdf.fill_color "000000"
    pdf.move_down 10
  end

  def add_seller_greeting(pdf)
    date_str = (order.shipped_at || order.delivered_at || order.created_at || Date.current).strftime("%b %d, %Y")

    pdf.text "<b>Date :</b> #{date_str}", inline_format: true, size: 9
    pdf.text "<b>To :</b> #{seller_business_name}", inline_format: true, size: 9, style: :bold
    pdf.move_down 6

    pdf.text "<b>Dear Sir/Madam,</b>", inline_format: true, size: 9
    pdf.text "We are pleased to inform you that the order has been confirmed for fulfillment as per the details mentioned below:", size: 8.5
    pdf.move_down 10
  end

  def add_order_details_table(pdf)
    pdf.text "1. Product & Order Details", style: :bold, size: 9.5, color: "0047AB"
    pdf.move_down 4

    rows = [
      ["A", "Order Reference ID", order_reference],
      ["B", "Customer", customer_identifier_value],
      ["C", "Product", first_product_name],
      ["D", "Brand | Category", brand_category_display],
      ["E", "Model Number / Color", model_variant_color_display],
      ["F", "Total Quantity (QTY)", total_quantity_display],
      ["G", "Order Type", order_source_type_display],
      ["H", "Order Date & Time", (order.created_at || Date.current).strftime("%b %d, %Y %I:%M %p")],
      ["I", "Payment Method", is_cod? ? "COD (Cash On Delivery)" : "Online Prepaid"]
    ]

    if serial_numbers_display.present?
      rows << ["J", "Serial Number(s)", serial_numbers_display]
    end

    pdf.table(
      rows,
      column_widths: [30, 200, pdf.bounds.width - 230],
      cell_style: {
        size: 8.5,
        padding: [4, 6],
        border_width: 0.5,
        border_color: "0047AB"
      }
    ) do
      columns(0).align = :center
      columns(0).font_style = :bold
      columns(1).font_style = :bold
    end

    pdf.move_down 12
  end

  def add_disbursement_breakup_table(pdf)
    section_title = is_cod? ? "2. Platform Commission & COD Fee Recovery Break-Up (in ₹)" : "2. Disbursement Break-Up (in ₹)"
    pdf.text section_title, style: :bold, size: 9.5, color: "0047AB"
    pdf.move_down 4

    gross_val = order.total_amount.to_f
    fee_pct = platform_fee_percentage
    fee_amount = (gross_val * fee_pct / 100.0).round(2)
    net_disburse = (gross_val - fee_amount).round(2)

    rows = if is_cod?
      [
        ["A", "Total Product Cost / Order Value (Collected by Seller from Customer)", currency(gross_val)],
        ["B", "SalesPoints Platform Commission Fee Rate", "#{format('%.2f', fee_pct)}%"],
        ["C", "Platform Fee Amount Owed to SalesPoints", currency(fee_amount)],
        ["D=C", "Net Amount to be Recovered / Adjusted by SalesPoints from Payout", currency(fee_amount)]
      ]
    else
      [
        ["A", "Total Gross Product / Order Value", currency(gross_val)],
        ["B", "SalesPoints Platform Commission Fee Rate", "#{format('%.2f', fee_pct)}%"],
        ["C", "Platform Fee Deducted by SalesPoints", "- #{currency(fee_amount)}"],
        ["D=A-C", "Net Disbursement Amount Payable to Seller", currency(net_disburse)]
      ]
    end

    cod_flag = is_cod?

    pdf.table(
      rows,
      column_widths: [70, 280, pdf.bounds.width - 350],
      cell_style: {
        size: 8.5,
        padding: [4, 6],
        border_width: 0.5,
        border_color: "0047AB"
      }
    ) do
      columns(0).align = :center
      columns(0).font_style = :bold
      columns(1).font_style = :bold
      columns(2).align = :right
      row(-1).font_style = :bold
      row(-1).background_color = cod_flag ? "FFF0F5" : "F0FFF0"
    end

    pdf.move_down 4

    note_text = if is_cod?
      "<b>Note (COD Settlement):</b> Since this is a Cash On Delivery (COD) order, you collect the full order amount (#{currency(gross_val)}) directly from the customer. SalesPoints will recover the platform commission fee of <b>#{currency(fee_amount)}</b> by deducting/adjusting it from your online payout balance."
    else
      "<b>Note (Online Disbursement):</b> Payment has been collected online by SalesPoints. SalesPoints will disburse <b>#{currency(net_disburse)}</b> directly to your registered bank account after deducting the platform commission fee of #{currency(fee_amount)} and COD charges."
    end

    pdf.text note_text, inline_format: true, size: 7.5, color: "555555"

    pdf.move_down 12
  end

  def add_shipping_address_box(pdf)
    pdf.text "3. Customer Delivery Address", style: :bold, size: 9.5, color: "0047AB"
    pdf.move_down 4

    pdf.bounding_box([0, pdf.cursor], width: pdf.bounds.width) do
      pdf.stroke_color "0047AB"
      pdf.stroke_bounds
      pdf.pad(8) do
        pdf.indent(10) do
          pdf.text "<b>Delivery Address:</b>", inline_format: true, size: 9, color: "0047AB"
          pdf.move_down 4
          pdf.text shipping_address_formatted, size: 8.5, leading: 3
        end
      end
    end

    pdf.move_down 12
  end

  def add_terms_and_conditions(pdf)
    pdf.text "<b>Terms & Conditions & Instructions:</b>", inline_format: true, size: 9, color: "0047AB"
    pdf.move_down 4

    terms = [
      "1. This is a computer generated delivery order and does not require physical signature.",
      "2. Products must be delivered strictly to the Customer Delivery Address mentioned above.",
      "3. Before handing over goods, verified serial numbers/IMEI (where applicable) must be verified.",
      "4. Seller is responsible for ensuring original packaging and intact warranty seals during dispatch.",
      "5. In case of delivery failure, customer refusal, or address untraceability, contact SalesPoints support immediately at support.salespoints.in@gmail.com.",
      "6. SalesPoints India Private Limited acts as the marketplace intermediator."
    ]

    terms.each do |term|
      pdf.text term, size: 7.5, color: "444444", leading: 2
    end

    pdf.move_down 8
  end

  def add_footer(pdf)
    pdf.stroke_horizontal_rule
    pdf.move_down 6

    pdf.text "Thanking you,", size: 8
    pdf.move_down 8
    pdf.text "<b>SalesPoints India Private Limited</b>", inline_format: true, size: 8.5, color: "1E3A8A"
    pdf.text "Marketplace Facilitator", size: 8, color: "666666"

  end

  # ============ HELPERS ============

  def is_b2b?
    order.is_a?(B2bOrder)
  end

  def is_cod?
    order.payment_method.to_s.downcase == "cod"
  end

  def seller
    order.seller_dealer
  end

  def seller_business_name
    return "SALESPOINTS DEALER STORE" if seller.blank?
    bname = seller.try(:dealer_profile)&.business_name.presence
    bname ||= seller.try(:full_name).presence || seller.try(:name).presence || seller.try(:dealer_code).presence
    bname.upcase
  end

  def customer_identifier_value
    if is_b2b?
      buyer_dealer = order.buyer_dealer
      buyer_dealer&.try(:dealer_code).presence || "DEALER"
    else
      buyer = order.buyer
      buyer&.try(:full_name).presence || buyer&.try(:first_name).presence || "Customer"
    end
  end

  def order_reference
    is_b2b? ? order.reference_number : order.order_number
  end

  def order_source_type_display
    if is_b2b?
      stype = order.try(:source_type).to_s
      stype == "WholesalerPost" ? "Wholesale Direct" : "B2B Network"
    else
      "Retail Marketplace"
    end
  end

  def order_items
    is_b2b? ? order.b2b_order_items : order.order_items
  end

  def first_product_name
    items = order_items
    return "Product Item" if items.blank?

    items.map do |item|
      item.try(:product_name).presence ||
      item.try(:product_variant)&.product&.name.presence ||
      item.try(:wholesaler_post)&.title.presence ||
      "Product Item"
    end.join(", ")
  end

  def brand_category_display
    items = order_items
    return "N/A" if items.blank?

    brand_cat_list = items.map do |item|
      p = item.try(:product_variant)&.product
      b_name = p&.brand&.name.presence || "Brand"
      c_name = p&.category&.name.presence || "Category"
      "#{b_name} | #{c_name}"
    end.uniq

    brand_cat_list.join("; ")
  end

  def model_variant_color_display
    items = order_items
    return "N/A" if items.blank?

    items.map do |item|
      sku = item.try(:variant_sku).presence ||
            item.try(:product_variant)&.variant_sku.presence ||
            item.try(:wholesaler_post)&.modal_no.presence ||
            "Standard"

      color = if item.respond_to?(:color) && item.color.present?
                item.color
              elsif item.respond_to?(:product_variant_color) && item.product_variant_color
                item.product_variant_color.color_name
              else
                nil
              end

      color ? "#{sku} (#{color})" : sku
    end.join(", ")
  end

  def total_quantity_display
    order_items.sum { |i| i.quantity.to_i }.to_s
  end

  def serial_numbers_display
    dc = active_delivery_confirmation
    return nil if dc.blank? || dc.serial_numbers.blank?

    dc.serial_numbers.join(", ")
  end

  def active_delivery_confirmation
    @active_delivery_confirmation ||= order.try(:replacement_delivery_confirmation).presence || order.try(:delivery_confirmation)
  end

  def platform_fee_percentage
    if order.respond_to?(:commission_rate) && order.commission_rate.to_f > 0
      order.commission_rate.to_f
    elsif is_b2b?
      1.50
    else
      2.50
    end
  end

  def shipping_address_formatted
    addr = order.shipping_address
    return "N/A" if addr.blank?

    case addr
    when Hash, ActionController::Parameters
      [
        addr["address_line1"] || addr[:address_line1],
        addr["address_line2"] || addr[:address_line2],
        addr["city"] || addr[:city],
        addr["state"] || addr[:state],
        addr["postal_code"] || addr[:postal_code] || addr["pincode"] || addr[:pincode]
      ].compact.reject(&:blank?).join("\n")
    when String
      addr
    else
      addr.try(:full_address).presence || "N/A"
    end
  end

  def currency(val)
    "₹ #{format('%.2f', val.to_f)}"
  end
end
