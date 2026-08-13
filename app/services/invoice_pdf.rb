require 'prawn'
require 'prawn/table'

class InvoicePdf
  attr_reader :order

  GST_STATE_CODES = {
    "01" => "Jammu and Kashmir", "02" => "Himachal Pradesh", "03" => "Punjab",
    "04" => "Chandigarh", "05" => "Uttarakhand", "06" => "Haryana",
    "07" => "Delhi", "08" => "Rajasthan", "09" => "Uttar Pradesh",
    "10" => "Bihar", "11" => "Sikkim", "18" => "Assam", "19" => "West Bengal",
    "20" => "Jharkhand", "21" => "Odisha", "22" => "Chhattisgarh",
    "23" => "Madhya Pradesh", "24" => "Gujarat", "27" => "Maharashtra",
    "29" => "Karnataka", "30" => "Goa", "32" => "Kerala", "33" => "Tamil Nadu",
    "36" => "Telangana", "37" => "Andhra Pradesh"
  }.freeze

  STATE_ABBREVIATIONS = {
    "01" => "JK", "02" => "HP", "03" => "PB", "04" => "CH", "05" => "UK",
    "06" => "HR", "07" => "DL", "08" => "RJ", "09" => "UP", "10" => "BR",
    "11" => "SK", "18" => "AS", "19" => "WB", "20" => "JH", "21" => "OR",
    "22" => "CG", "23" => "MP", "24" => "GJ", "27" => "MH", "29" => "KA",
    "30" => "GA", "32" => "KL", "33" => "TN", "36" => "TS", "37" => "AP"
  }.freeze

  REVERSE_GST_STATE_CODES = GST_STATE_CODES.invert.transform_keys { |k| k.downcase.gsub(/\s+/, "") }.freeze

  DEFAULT_TAX_RATE = 18.0

  def initialize(order)
    @order = order
  end

  def generate
    pdf = Prawn::Document.new(
      page_size: "A4",
      margin: 15,
      info: { Title: "Invoice #{invoice_number}" }
    )

    pdf.font_families.update(
      "DejaVu" => {
        normal: Rails.root.join("app/assets/fonts/DejaVuSans.ttf"),
        bold: Rails.root.join("app/assets/fonts/DejaVuSans-Bold.ttf"),
        italic: Rails.root.join("app/assets/fonts/DejaVuSans-Oblique.ttf"),
        bold_italic: Rails.root.join("app/assets/fonts/DejaVuSans-BoldOblique.ttf")
      }
    )

    pdf.font "DejaVu"
    pdf.font_size 9
    
    add_company_header(pdf)
    add_invoice_header(pdf)
    add_billing_shipping(pdf)
    add_items_table(pdf)
    add_totals(pdf)
    add_signature(pdf)
    add_footer(pdf)
    
    pdf.render
  end

  private

  def invoice_number
    @invoice_number ||= begin
      if @order.invoice_number.present?
        @order.invoice_number
      else
        generated_number = nil

        5.times do
          number = generate_invoice_number

          begin
            @order.update!(invoice_number: number)
            generated_number = number
            break
          rescue ActiveRecord::RecordNotUnique
            next
          end
        end

        raise "Unable to generate unique invoice number" unless generated_number

        generated_number
      end
    end
  end

  def generate_invoice_number
    financial_year = current_financial_year
    klass = @order.is_a?(B2bOrder) ? B2bOrder : Order

    last_invoice = klass
                    .where("invoice_number LIKE ?", "SPIN/#{financial_year}/%")
                    .order(invoice_number: :desc)
                    .first

    serial =
      if last_invoice&.invoice_number.present?
        last_invoice.invoice_number.split("/").last.to_i + 1
      else
        1
      end

    "SPIN/#{financial_year}/#{serial.to_s.rjust(5, '0')}"
  end

  def current_financial_year
    date = Date.current
    year = date.year
    month = date.month
    
    if month >= 4
      "#{year}-#{(year + 1).to_s[-2..-1]}"
    else
      "#{year - 1}-#{year.to_s[-2..-1]}"
    end
  end

  def invoice_date
    @order.shipped_at || @order.delivered_at || Date.current
  end

  # ============ SELLER DETAILS ============
  
  def seller
    @seller ||= @order.is_a?(B2bOrder) ? @order.seller_dealer : @order.seller_dealer
  end

  def seller_name
    seller&.dealer_code || "SalesPoints Seller"
  end

  def seller_gstin
    return "N/A" if seller.blank?
    seller.dealer_profile&.gst_number || "N/A"
  end

  def seller_pan
    return "N/A" if seller.blank?
    seller.dealer_profile&.pan_number || "N/A"
  end

  def seller_cin
    return "N/A" if seller.blank?
    "N/A"
  end

  def seller_address
    seller&.dealer_profile&.business_address || "302, Solitaire, Sunrise Park, Vastrapur, AHMEDABAD, GUJARAT - 380054"
  end

  def seller_state
    "DELHI"
  end

  def seller_state_code
    "DL-07"
  end

  # ============ BUYER DETAILS ============
  
  def buyer
    @buyer ||= @order.is_a?(B2bOrder) ? @order.buyer_dealer : @order.buyer
  end

  def buyer_name
    if buyer.present?
      buyer.full_name || buyer.dealer_code || "Customer"
    else
      "Customer"
    end
  end

  def buyer_gstin
    return "N/A" if buyer.blank?
    if buyer.respond_to?(:gst_number)
      buyer.gst_number || "N/A"
    elsif buyer.respond_to?(:dealer_profile) && buyer.dealer_profile&.gst_number
      buyer.dealer_profile.gst_number
    else
      "N/A"
    end
  end

  def raw_shipping_address
    return @order.shipping_address if @order.shipping_address.present?
    return nil if buyer.blank?
    
    if buyer.respond_to?(:dealer_profile) && buyer.dealer_profile&.business_address.present?
      buyer.dealer_profile.business_address
    elsif buyer.respond_to?(:addresses) && buyer.addresses.present?
      buyer.addresses.first
    else
      nil
    end
  end

  def raw_billing_address
    return @order.billing_address if @order.billing_address.present?

    raw_shipping_address
  end

  def raw_buyer_address
    raw_shipping_address
  end

  def shipping_address_str
    format_address(raw_shipping_address)
  end

  def billing_address_str
    format_address(raw_billing_address)
  end

  def buyer_address
    shipping_address_str
  end

  def buyer_phone
    phone = buyer&.try(:phone)
    phone ||= @order.shipping_address&.dig("phone") if @order.shipping_address.is_a?(Hash)
    phone || "N/A"
  end

  def buyer_state
    address = raw_shipping_address
    state_str = nil
    
    case address
    when Hash, ActionController::Parameters
      state_str = address["state"] || address[:state]
    when String
      state_str = nil
    else
      state_str = address.try(:state)
    end
    
    state_str.presence || "Delhi"
  end

  def buyer_state_code
    state = buyer_state.to_s.downcase.gsub(/\s+/, "")
    code = REVERSE_GST_STATE_CODES[state] || "07"
    abbr = STATE_ABBREVIATIONS[code] || "DL"
    "#{abbr}-#{code}"
  end

  def format_address(address)
    return "N/A" if address.blank?
    
    case address
    when Hash, ActionController::Parameters
      [
        address["address_line1"] || address[:address_line1],
        address["address_line2"] || address[:address_line2],
        address["city"] || address[:city],
        address["state"] || address[:state],
        address["postal_code"] || address[:postal_code] || address["pincode"] || address[:pincode]
      ].compact.reject(&:blank?).join(", ")
    when String
      address
    else
      if address.respond_to?(:full_address)
        address.full_address
      elsif address.respond_to?(:as_order_payload)
        format_address(address.as_order_payload)
      else
        [
          address.try(:address_line1),
          address.try(:address_line2),
          address.try(:city),
          address.try(:state),
          address.try(:postal_code)
        ].compact.reject(&:blank?).join(", ").presence || "N/A"
      end
    end
  end

  # ============ ORDER DETAILS ============
  
  def order_reference
    @order.is_a?(B2bOrder) ? @order.reference_number : @order.order_number
  end

  def order_date
    @order.created_at.to_date
  end

  def subtotal
    @order.subtotal_amount.to_f
  end

  def discount
    @order.discount_amount.to_f
  end

  def taxable_value
    @order.subtotal_amount.to_d - @order.tax_amount.to_d
  end

  def order_items
    if @order.is_a?(B2bOrder)
      @order.b2b_order_items
    else
      @order.order_items
    end
  end

  # ============ TAX CALCULATION ============
  
  def tax_type
    seller_state_code == buyer_state_code ? "CGST_SGST" : "IGST"
  end

  def igst_rate
    tax_type == "IGST" ? 18.0 : 0.0
  end

  def cgst_rate
    tax_type == "CGST_SGST" ? 9.0 : 0.0
  end

  def sgst_rate
    tax_type == "CGST_SGST" ? 9.0 : 0.0
  end

  def igst_amount
    if tax_type == "IGST"
      (taxable_value * igst_rate / 100).round(2)
    else
      0.0
    end
  end

  def cgst_amount
    if tax_type == "CGST_SGST"
      (taxable_value * cgst_rate / 100).round(2)
    else
      0.0
    end
  end

  def sgst_amount
    if tax_type == "CGST_SGST"
      (taxable_value * sgst_rate / 100).round(2)
    else
      0.0
    end
  end

  def total_amount
    taxable_value + igst_amount + cgst_amount + sgst_amount
  end

  def tax_label
    tax_type == "IGST" ? "IGST" : "CGST/SGST"
  end

  def tax_amount
    igst_amount + cgst_amount + sgst_amount
  end

  def currency(amount)
    "₹ #{format('%.2f', amount)}"
  end

  # ============ PDF METHODS ============

  def add_company_header(pdf)
    pdf.text "Tax Invoice", size: 14, align: :center
    pdf.move_down 8
  end

  def add_invoice_header(pdf)
    pdf.bounding_box([0, pdf.cursor], width: pdf.bounds.width) do
      pdf.text "SALESPOINTS INDIA PRIVATE LIMITED", size: 10, style: :bold, align: :center
      pdf.text "Reg. Off: H-105, Street No. 13, Karawal Nagar, Bhajanpura, Delhi - 110055, IN-DL", size: 8, align: :center
      pdf.text "support@salespoints.in | +91-8368835228 | www.salespoints.in", size: 8, align: :center
      pdf.text "GSTIN - 07ABTCS6593H1ZH | CIN - U46524DC2026PTC471107", size: 8, align: :center
    end
    pdf.move_down 12
  end

  def add_billing_shipping(pdf)
    pdf.stroke_horizontal_rule
    pdf.move_down 8

    order_details = <<~TEXT
    <b>Invoice Date:</b> #{invoice_date.strftime('%d-%m-%Y')}
    <b>Invoice No:</b> #{invoice_number}

    <b>Order Date:</b> #{order_date.strftime('%d-%m-%Y')}
    <b>Order ID:</b> #{order_reference}

    <b>Verified Seller:</b> #{seller_name}
    <b>PAN:</b> ABTCS6593H
    TEXT

    bill_to = <<~TEXT
    <b>Bill To</b>
    #{buyer_name}

    #{billing_address_str.to_s}

    Phone: #{buyer_phone}
    State: #{buyer_state_code} #{buyer_state}
    GSTIN: #{buyer_gstin}
    TEXT

    ship_to = <<~TEXT
    <b>Ship To</b>
    #{buyer_name}

    #{shipping_address_str.to_s}

    Phone: #{buyer_phone}
    TEXT

    pdf.table(
      [[order_details, bill_to, ship_to]],
      column_widths: [165, 200, 200],
      cell_style: {
        borders: [:top, :bottom],
        border_width: 0.5,
        border_color: "CCCCCC",
        padding: [6, 8],
        size: 8,
        inline_format: true,
        valign: :top,
        leading: 2
      }
    )

    pdf.move_down 10

    pdf.text "Total items: #{order_items.count}", size: 10

    pdf.stroke_horizontal_rule
    pdf.move_down 8
  end

  def add_items_table(pdf)
    data = [[
      "Product",
      "HSN",
      "Qty",
      "Unit\nPrice",
      "Dis.",
      "Taxable\nValue",
      "CGST",
      "SGST",
      "IGST",
      "Total"
    ]]
    order_items.each do |item|
      product = item.product_variant&.product

      serial_text = ""
      if @order.delivery_confirmation&.serial_numbers.present?
        serial_text = "Serial No(s):\n" + @order.delivery_confirmation.serial_numbers.join(", ")
      end

      sku = item.product_variant&.variant_sku || item&.wholesaler_post&.modal_no || 'Standard'
      color = item.respond_to?(:product_variant_color) && item.product_variant_color ? item.product_variant_color.color_name : (item.respond_to?(:ad_hoc_color) ? item.ad_hoc_color : nil)
      color_text = color.present? ? " - #{color}" : ""

      left = <<~TEXT
      <b>#{product&.name || item&.wholesaler_post&.title || 'Product'}</b>

      #{sku}#{color_text}

      #{serial_text}

      #{tax_label}: #{product&.tax_rate || 18} %
      TEXT
      
      data << [
        left,
        "85171300",
        item.quantity,
        format('%.2f', item.unit_price),
        format('%.2f', discount),
        format('%.2f', taxable_value),
        format('%.2f', cgst_amount),
        format('%.2f', sgst_amount),
        format('%.2f', igst_amount),
        format('%.2f', total_amount)
      ]
    end

    data << [
      "",
      "<b>Total</b>",
      order_items.sum(&:quantity),
      format('%.2f', subtotal),
      format('%.2f', discount),
      format('%.2f', taxable_value),
      format('%.2f', cgst_amount),
      format('%.2f', sgst_amount),
      format('%.2f', igst_amount),
      format('%.2f', total_amount)
    ]
    
    pdf.table(
      data,
      header: true,
      cell_style: {
        size: 8,
        padding: [6, 6],
        leading: 2,
        inline_format: true,
        valign: :center,
        align: :center,
        border_width: 0.5,
        border_color: "999999"
      },
      column_widths: {
        0 => 140,
        1 => 60,
        2 => 30,
        3 => 50,
        4 => 30,
        5 => 50,
        6 => 50,
        7 => 50,
        8 => 50,
        9 => 55
      }
    ) do
      row(0).font_style = :bold
      row(0).background_color = "EFEFEF"
      row(0).height = 42
      row(0).align = :center
      row(0).valign = :center

      columns(0).overflow = :shrink_to_fit
      columns(0).min_font_size = 6
      columns(0).align = :left
      columns(0).valign = :center
      columns(0).padding = [8,8]

      columns(1).padding = [8,8]
      columns(1).valign = :center
      columns(1).overflow = :shrink_to_fit
      columns(1).min_font_size = 6

      columns(2..9).align = :center
      columns(2..9).valign = :center
      columns(2..9).padding = [4, 4]

      row(-1).font_style = :bold
      row(-1).background_color = "F8F8F8"
      row(-1).align = :center
      row(-1).valign = :center
    end
  end

  def add_totals(pdf)
    pdf.move_down 12

    pdf.text(
      "<b>Grand Total:     #{currency(total_amount)}</b>",
      inline_format: true,
      align: :right,
      size: 11
    )
  end
  
  def add_signature(pdf)

    pdf.move_down 20

    pdf.bounding_box([pdf.bounds.right-170,pdf.cursor],width:170) do

      pdf.text "For SalesPoints India Pvt Ltd",
        align: :center,
        style: :bold,
        size: 9

      pdf.move_down 8

      signature_path = Rails.root.join("app/assets/images/sign.png")

      if File.exist?(signature_path)
        pdf.image signature_path,
          width: 90,
          position: :center
      else
        pdf.move_down 30
      end

      pdf.move_down 5

      pdf.text "Authorized Signatory",
        align: :center,
        style: :bold,
        size: 9

    end
  end

  def add_footer(pdf)

    pdf.move_down 25

    pdf.stroke_horizontal_rule

    pdf.move_down 8

    pdf.text(
      "Return/Replacement: Returns/Replacement accepted within 48 hours of delivery. Product must be unused with original packaging. " \
      "Refund processed within 5-7 working days post-quality check. Contact support@salespoints.in directly for replacement initiation. " ,
      size: 7,
      color: "666666"
    )

    pdf.move_down 4

    pdf.text(
      "Warranty Details: All products sold are covered under the manufacturer's warranty as applicable. " \
      "SalesPoints India Pvt Ltd acts as a marketplace facilitator and is not liable for " \
      "product quality, performance, or warranty claims beyond the scope of marketplace intermediation. " \
      "The seller is solely responsible for product quality and warranty claims. " \
      "Please keep the original invoice and manufacturer's packaging for warranty.",
      size: 7,
      color: "666666"
    )

    pdf.move_down 4

    pdf.text(
      "This product is delivered by our verified store seller code - #{seller_name}. " \
      "Salespoints India Pvt. Ltd. is the trusted marketplace intermediator.",
      size: 7,
      color: "666666"
    )

  end
end