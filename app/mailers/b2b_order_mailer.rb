class B2bOrderMailer < ApplicationMailer
  default from: "Sales Points <salespointecom@gmail.com>"

  def acceptance_update(order_id, seller_id, item_ids)
    @order = B2bOrder.includes(:buyer_dealer, b2b_order_items: [product_variant: :product]).find(order_id)
    @seller = Dealer.find(seller_id)
    @items = @order.b2b_order_items.where(id: item_ids)
    return if @order.buyer_dealer.email.blank?

    item_lines = @items.map do |item|
      "#{item.product_variant&.product&.name || item.product_variant&.variant_sku || 'Item'} x #{item.quantity}"
    end.join("\n")

    mail(
      to: @order.buyer_dealer.email,
      subject: "B2B request ##{@order.id} accepted by #{@seller.dealer_code}",
      body: <<~BODY
        Hello #{@order.buyer_dealer.dealer_code || "Dealer"},

        #{@seller.dealer_code} accepted part of your B2B request ##{@order.id}.

        Accepted items:
        #{item_lines}

        Current order status: #{@order.reload.status.humanize}
        Current allocated total: Rs #{@order.total_amount.to_f.round(2)}

        Please open SalesPoints to review the latest allocation.
      BODY
    )
  end

  def delivery_invoice(order_id, recipient_kind)
    @order = B2bOrder.includes(:buyer_dealer, :seller_dealer, :delivery_confirmation).find(order_id)
    recipient_kind = recipient_kind.to_s
    recipient =
      if recipient_kind == "seller"
        @order.seller_dealer
      else
        @order.buyer_dealer
      end

    return if recipient&.email.blank?

    recipient_name = recipient.full_name.presence || recipient.dealer_code || "Dealer"
    invoice_time = @order.shipped_at || @order.delivery_confirmation&.invoice_reference_time || Time.current

    mail(
      to: recipient.email,
      subject: "Invoice for B2B order #{@order.reference_number}",
      body: <<~BODY
        Hello #{recipient_name},

        B2B order #{@order.reference_number} has been delivered and verified through delivery proof plus dual OTP confirmation.

        Invoice reference date: #{invoice_time.strftime("%d %b %Y %I:%M %p")}
        Order amount: Rs #{@order.total_amount.to_f.round(2)}
        Payment method: #{@order.payment_method.to_s.upcase}
        Payment status: #{@order.payment_status.to_s.upcase}
        Delivery status: #{@order.status.to_s.humanize}

        Please keep this email for your invoice reference.
      BODY
    )
  end
end
