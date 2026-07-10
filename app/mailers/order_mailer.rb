class OrderMailer < ApplicationMailer
  default from: "Sales Points <salespointecom@gmail.com>"

  def customer_order_confirmation(order_id)
    @order = Order.includes(:buyer, :seller_dealer).find(order_id)
    return if @order.buyer&.email.blank?

    mail(
      to: @order.buyer.email,
      subject: "Order #{@order.order_number} placed successfully",
      body: <<~BODY
        Hello #{@order.buyer.respond_to?(:full_name) ? @order.buyer.full_name : "Customer"},

        Your order #{@order.order_number} has been placed successfully.
        Total amount: Rs #{@order.total_amount.to_f.round(2)}
        Payment method: #{@order.payment_method.to_s.upcase}
        Payment status: #{@order.payment_status.to_s.upcase}
        Status: #{@order.status.to_s.humanize}

        Thank you for shopping with SalesPoints.
      BODY
    )
  end

  def dealer_new_order(order_id)
    @order = Order.includes(:buyer, :seller_dealer).find(order_id)
    return if @order.seller_dealer&.email.blank?

    buyer_name = if @order.buyer.respond_to?(:full_name)
      @order.buyer.full_name
    else
      @order.buyer&.email || "Customer"
    end

    mail(
      to: @order.seller_dealer.email,
      subject: "New order #{@order.order_number} received",
      body: <<~BODY
        Hello #{@order.seller_dealer.full_name.presence || @order.seller_dealer.dealer_code},

        You have received a new order #{@order.order_number}.
        Buyer: #{buyer_name}
        Total amount: Rs #{@order.total_amount.to_f.round(2)}
        Payment status: #{@order.payment_status.to_s.upcase}

        Please open your dashboard to process the order.
      BODY
    )
  end

  def admin_order_alert(order_id)
    @order = Order.includes(:buyer).find(order_id)

    admin_emails = AdminUser.where(is_super_admin: true).where.not(email: [nil, ""]).pluck(:email)
    return if admin_emails.empty?

    mail(
      to: admin_emails.first,
      bcc: admin_emails.drop(1),
      subject: "New order #{@order.order_number} placed",
      body: <<~BODY
        A new order has been placed on SalesPoints.

        Order: #{@order.order_number}
        Buyer: #{@order.buyer.respond_to?(:full_name) ? @order.buyer.full_name : @order.buyer&.email}
        Total amount: Rs #{@order.total_amount.to_f.round(2)}
        Payment method: #{@order.payment_method.to_s.upcase}
        Payment status: #{@order.payment_status.to_s.upcase}
      BODY
    )
  end

  def order_status_update(order_id)
    @order = Order.includes(:buyer, :seller_dealer).find(order_id)
    return if @order.buyer&.email.blank?

    mail(
      to: @order.buyer.email,
      subject: "Order #{@order.order_number} updated to #{@order.status.to_s.humanize}",
      body: <<~BODY
        Hello #{@order.buyer.respond_to?(:full_name) ? @order.buyer.full_name : "Customer"},

        Your order #{@order.order_number} is now #{@order.status.to_s.humanize}.
        Payment status: #{@order.payment_status.to_s.upcase}

        Thank you for using SalesPoints.
      BODY
    )
  end

  def delivery_invoice(order_id, recipient_kind)
    @order = Order.includes(:buyer, :seller_dealer, :delivery_confirmation).find(order_id)
    recipient_kind = recipient_kind.to_s
    recipient_email =
      if recipient_kind == "seller"
        @order.seller_dealer&.email
      else
        @order.buyer&.email
      end

    return if recipient_email.blank?

    recipient_name =
      if recipient_kind == "seller"
        @order.seller_dealer&.full_name.presence || @order.seller_dealer&.dealer_code || "Seller"
      else
        @order.buyer.respond_to?(:full_name) ? @order.buyer.full_name : "Customer"
      end

    invoice_time = @order.shipped_at || @order.delivery_confirmation&.invoice_reference_time || Time.current

    mail(
      to: recipient_email,
      subject: "Invoice for order #{@order.order_number}",
      body: <<~BODY
        Hello #{recipient_name},

        Order #{@order.order_number} has been successfully delivered and verified through seller/buyer OTP confirmation.

        Invoice reference date: #{invoice_time.strftime("%d %b %Y %I:%M %p")}
        Order amount: Rs #{@order.total_amount.to_f.round(2)}
        Payment method: #{@order.payment_method.to_s.upcase}
        Payment status: #{@order.payment_status.to_s.upcase}
        Delivery status: #{@order.status.to_s.humanize}

        You can also download the invoice anytime from your SalesPoints orders section.
      BODY
    )
  end
end
