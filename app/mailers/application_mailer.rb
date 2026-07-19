class ApplicationMailer < ActionMailer::Base
  default from: "SalesPoints <salespointecom@gmail.com>"
  layout "mailer"

  helper_method :format_currency, :format_date, :payment_method_label, :format_address
  
  private
  
  def format_currency(amount)
    "₹#{amount.to_f.round(2)}"
  end
  
  def format_date(date)
    date.present? ? date.strftime("%d %B, %Y at %I:%M %p") : "N/A"
  end
  
  def payment_method_label(method)
    case method.to_s.downcase
    when "upi" then "UPI"
    when "card", "credit_card", "debit_card" then "Card"
    when "netbanking" then "Net Banking"
    when "cod" then "Cash on Delivery"
    when "online" then "Online Payment"
    else method.to_s.upcase
    end
  end

  def format_address(address)
    return "N/A" if address.blank?
    
    case address
    when Hash
      [
        address["address_line1"],
        address["address_line2"],
        address["city"],
        address["state"],
        address["postal_code"],
        address["country"]
      ].compact.reject(&:blank?).join(", ")
    when ActionController::Parameters
      format_address(address.to_unsafe_h)
    else
      address.to_s
    end
  end
  
  def payment_details(order)
    {
      method: payment_method_label(order.payment_method),
      status: order.payment_status.to_s.upcase,
      reference: order.payment_reference || order.gateway_order_reference || "N/A",
      paid_at: order.paid_at || order.payment_confirmed_at
    }
  end
end