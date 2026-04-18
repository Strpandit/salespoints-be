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
end
