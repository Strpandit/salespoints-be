require 'prawn'
require 'prawn/table'

class InvoicePdf
  attr_reader :order

  def initialize(order)
    @order = order
  end

  def generate
    pdf = Prawn::Document.new(
      page_size: "A4",
      margin: 30,
      info: { Title: "Invoice #{invoice_number}" }
    )
    
    add_company_header(pdf)
    add_invoice_header(pdf)
    add_billing_shipping(pdf)
    add_items_table(pdf)
    add_totals(pdf)
    add_footer(pdf)
    
    pdf.render
  end

  private

  def invoice_number
    @invoice_number ||= generate_invoice_number
  end

  def generate_invoice_number
    financial_year = current_financial_year
    
    # Count existing invoices for this order type
    count = if @order.is_a?(B2bOrder)
      B2bOrder.where("reference_number LIKE ?", "SPIN-#{financial_year}-%").count
    else
      Order.where("order_number LIKE ?", "SPIN-#{financial_year}-%").count
    end
    
    "SPIN-#{financial_year}-#{(count + 1).to_s.rjust(5, '0')}"
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
    seller&.full_name || seller&.dealer_code || "SalesPoints"
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
    "IN-DL"
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

  def buyer_address
    return "N/A" if buyer.blank?
    
    if buyer.respond_to?(:dealer_profile) && buyer.dealer_profile&.business_address.present?
      buyer.dealer_profile.business_address
    elsif buyer.respond_to?(:addresses)
      address = buyer.addresses&.first
      address.present? ? format_address(address) : "N/A"
    elsif buyer.respond_to?(:shipping_address)
      format_address(buyer.shipping_address)
    else
      "N/A"
    end
  end

  def buyer_phone
    buyer&.phone || "N/A"
  end

  def buyer_state
    "Delhi"
  end

  def buyer_state_code
    "IN-DL"
  end

  def format_address(address)
    return "N/A" if address.blank?
    
    case address
    when Hash, ActionController::Parameters
      [
        address["address_line1"],
        address["address_line2"],
        address["city"],
        address["state"],
        address["postal_code"]
      ].compact.reject(&:blank?).join(", ")
    else
      address.to_s
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
    subtotal - discount
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

  def igst_amount
    (taxable_value * igst_rate / 100).round(2)
  end

  def cgst_rate
    tax_type == "CGST_SGST" ? 9.0 : 0.0
  end

  def cgst_amount
    (taxable_value * cgst_rate / 100).round(2)
  end

  def sgst_rate
    tax_type == "CGST_SGST" ? 9.0 : 0.0
  end

  def sgst_amount
    (taxable_value * sgst_rate / 100).round(2)
  end

  def total_amount
    taxable_value + igst_amount + cgst_amount + sgst_amount
  end

  def tax_label
    tax_type == "IGST" ? "IGST" : "CGST/SGST"
  end

  # ============ PDF METHODS ============

  def add_company_header(pdf)
    pdf.text "123503, Farukhnaqar, HARYANA, India - 122503, IN-HR", 
             size: 8, color: "666666", align: :center
    pdf.text "GSTIN - #{seller_gstin}", 
             size: 8, color: "666666", align: :center
    pdf.text "IRN - #{SecureRandom.hex(20)}", 
             size: 8, color: "666666", align: :center
    pdf.move_down 8
  end

  def add_invoice_header(pdf)
    pdf.bounding_box([0, pdf.cursor], width: pdf.bounds.width) do
      # Left Column
      pdf.bounding_box([0, pdf.cursor], width: pdf.bounds.width * 0.65) do
        pdf.text "Order ID: #{order_reference}", size: 10, style: :bold
        pdf.text "Order Date: #{order_date.strftime('%d-%m-%Y')}", size: 10
        pdf.text "Invoice Date: #{invoice_date.strftime('%d-%m-%Y')}", size: 10
        pdf.text "PAN: #{seller_pan}", size: 10
        pdf.text "CIN: #{seller_cin}", size: 10
      end
      
      # Right Column
      pdf.bounding_box([pdf.bounds.width * 0.65, pdf.cursor], width: pdf.bounds.width * 0.35) do
        pdf.text "SALESPOINTS", size: 16, style: :bold, color: "0F766E", align: :right
        pdf.text "www.salespoints.in", size: 8, color: "666666", align: :right
        pdf.text "Invoice No: #{invoice_number}", size: 8, color: "0F766E", align: :right, style: :bold
      end
    end
    
    pdf.move_down 12
  end

  def add_billing_shipping(pdf)
    pdf.bounding_box([0, pdf.cursor], width: pdf.bounds.width) do
      # Bill To
      pdf.bounding_box([0, pdf.cursor], width: pdf.bounds.width * 0.5) do
        pdf.text "Bill To", size: 10, style: :bold, color: "0F766E"
        pdf.text buyer_name, size: 10, style: :bold
        pdf.text buyer_address, size: 9
        pdf.text "Phone: #{buyer_phone}", size: 9
        pdf.text "GSTIN: #{buyer_gstin}", size: 9
        pdf.text "State: #{buyer_state}", size: 9
        pdf.text "State Code: #{buyer_state_code}", size: 9
        pdf.text "Place of Supply: #{buyer_state}", size: 9
      end
      
      # Ship To
      pdf.bounding_box([pdf.bounds.width * 0.5, pdf.cursor], width: pdf.bounds.width * 0.5) do
        pdf.text "Ship To", size: 10, style: :bold, color: "0F766E"
        pdf.text buyer_name, size: 10, style: :bold
        pdf.text buyer_address, size: 9
        pdf.text "Phone: #{buyer_phone}", size: 9
        pdf.text "GSTIN: #{buyer_gstin}", size: 9
        pdf.text "State: #{buyer_state}", size: 9
        pdf.text "State Code: #{buyer_state_code}", size: 9
        pdf.text "Place of Supply: #{buyer_state}", size: 9
      end
    end
    
    pdf.move_down 8
    pdf.text "\\*Keep this invoice and manufacturer box for warranty purposes.", 
             size: 8, color: "666666"
    pdf.text "Total items: #{order_items.count}", size: 10, style: :bold
    pdf.move_down 10
  end

  def add_items_table(pdf)
    table_data = [["Product", "Title", "Qty", "Gross Amount INR", "Discounts/Coupons INR", "Taxable Value INR", tax_label, "Total INR"]]
    
    order_items.each do |item|
      product_name = item.product_variant&.product&.name || "Product"
      
      table_data << [
        "Handsets",
        product_name.truncate(35),
        item.quantity.to_s,
        "%.2f" % item.total_price,
        "0.00",
        "%.2f" % item.total_price,
        "%.2f" % (item.total_price * 0.18),
        "%.2f" % (item.total_price * 1.18)
      ]
    end
    
    pdf.table(table_data,
      header: true,
      position: :center,
      cell_style: {
        size: 7,
        padding: [4, 4, 4, 4],
        borders: [:bottom],
        border_color: "E2E8F0",
        align: :center
      }
    ) do
      row(0).style(background: "0F766E", text_color: "FFFFFF", font_style: :bold, size: 7.5)
      columns(1).style(align: :left)
      columns(0).width = 50
      columns(2).width = 30
      columns(3).width = 60
      columns(4).width = 60
      columns(5).width = 60
      columns(6).width = 65
      columns(7).width = 65
    end
    
    pdf.move_down 8
    
    order_items.each_with_index do |item, index|
      pdf.text "#{index + 1}. [IMEI/Serial No: #{SecureRandom.alphanumeric(15).upcase}]", size: 7, color: "666666"
      pdf.text "Warranty: 1 Year Warranty on Handset and 6 Months Warranty on Accessories", size: 7, color: "666666"
      pdf.text "HSN/SAC: #{item.product_variant&.product&.hsn_code || '85171300'}", size: 7, color: "666666"
      pdf.text "#{tax_label}: 18.0 %", size: 7, color: "666666"
      pdf.move_down 2
    end
  end

  def add_totals(pdf)
    pdf.move_down 8
    
    pdf.bounding_box([pdf.bounds.width * 0.5, pdf.cursor], width: pdf.bounds.width * 0.5) do
      pdf.text "Subtotal: INR #{'%.2f' % subtotal}", align: :right, size: 10
      pdf.text "Discount: INR #{'%.2f' % discount}", align: :right, size: 10
      pdf.text "Taxable Value: INR #{'%.2f' % taxable_value}", align: :right, size: 10
      
      if tax_type == "IGST"
        pdf.text "IGST (#{igst_rate}%): INR #{'%.2f' % igst_amount}", align: :right, size: 10
      else
        pdf.text "CGST (#{cgst_rate}%): INR #{'%.2f' % cgst_amount}", align: :right, size: 10
        pdf.text "SGST (#{sgst_rate}%): INR #{'%.2f' % sgst_amount}", align: :right, size: 10
      end
      
      pdf.move_down 4
      pdf.text "Grand Total INR #{'%.2f' % total_amount}", 
              align: :right, size: 14, style: :bold, color: "0F766E"
    end
    
    pdf.move_down 20
  end

  def add_footer(pdf)
    pdf.text "SALESPOINTS", size: 14, style: :bold, color: "0F766E", align: :center
    pdf.move_down 2
    
    pdf.text "Authorized Signatory", size: 10, style: :italic, align: :center
    pdf.move_down 8
    
    pdf.text "Returns Policy: At SalesPoints we try to deliver perfectly each and every time. But in the off-chance that you need to return the item, please do so with the original Brand box/price tag, original packing and invoice without which it will be really difficult for us to act on your request. Please help us in helping you. Terms and conditions apply.", 
             size: 8, color: "666666", align: :center, inline_format: true
    
    pdf.move_down 6
    pdf.text "Regd. office: #{seller_address}", size: 8, color: "666666", align: :center
    pdf.move_down 4
    pdf.text "Contact: support@salespoints.in | www.salespoints.in", size: 8, color: "666666", align: :center
  end
end