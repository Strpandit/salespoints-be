class B2bOrderPaymentService
  def initialize(order_id:, payment_method:)
    @order_id = order_id
    @payment_method = payment_method.to_s.presence || "cod"
    @order = B2bOrder.find_by(id: order_id)
  end

  def call
    raise StandardError, "Order not found" unless @order
    raise StandardError, "Order is not in pending_payment state" unless @order.pending_payment?
    raise StandardError, "Invalid payment method" unless B2bOrder::PAYMENT_METHODS.include?(@payment_method)

    if @payment_method == "cod"
      @order.mark_payment_paid!
      @order.mark_order_confirmed!
      send_payment_success_to_buyer(@order)
      create_buyer_payment_success_notification(@order)
      create_seller_payment_success_notification(@order)
      notify_admin_order_confirmed(@order)
      return { order: @order, payment_method: "cod", status: "confirmed", message: "Order confirmed with COD" }
    else
      result = create_online_payment_attempt(@order)
      return { 
        order: @order, 
        payment_method: "online", 
        status: "pending", 
        payment_attempt: result[:payment_attempt],
        payment_data: result[:payment_data],
        message: "Payment initiated. Complete payment to confirm order."
      }
    end
  end

  def send_payment_success_to_buyer(order)
    buyer = order.buyer_dealer
    seller = order.seller_dealer
    items = order.b2b_order_items.accepted_items
    first_item = items.first
    variant = first_item&.product_variant
    product = variant&.product
    
    product_name = product&.name || "Product"
    variant_name = variant&.variant_sku || "Standard"
    unit_price = first_item&.unit_price || 0
    quantity = items.sum(&:quantity)
    total_amount = order.total_amount

    MetaWhatsappCloudService.new.send_payment_success(
      to: formatted_phone_for(buyer),
      product: product_name,                            
      variant: variant_name,                            
      quantity: quantity.to_s,                          
      unit_price: unit_price.to_f.round(2).to_s,        
      total_paid: total_amount.to_f.round(2).to_s,      
      payment_id: "COD",                                
      order_id: order.id.to_s,                          
      dealer_code: seller&.dealer_code || "N/A",        
      dealer_phone: formatted_phone_for(seller) || "N/A"
    )
  rescue StandardError => e
    Rails.logger.error("Failed to send payment_success template to buyer: #{e.message}")
  end

  def create_buyer_payment_success_notification(order)
    NotificationService.deliver(
      recipient: order.buyer_dealer,
      actor: order.buyer_dealer,
      notifiable: order,
      kind: "b2b_order_payment_success",
      title: "✅ Payment Successful!",
      message: "Your order ##{order.id} has been confirmed with COD.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
      payload: {
        order_id: order.id,
        total_amount: order.total_amount.to_f,
        payment_method: "COD"
      }
    )
  end

  def create_seller_payment_success_notification(order)
    NotificationService.deliver(
      recipient: order.seller_dealer,
      actor: order.buyer_dealer,
      notifiable: order,
      kind: "b2b_order_payment_confirmed_seller",
      title: "💰 Payment Confirmed!",
      message: "Buyer #{order.buyer_dealer.dealer_code} has confirmed payment for order ##{order.id}.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
      payload: {
        order_id: order.id,
        buyer_dealer_id: order.buyer_dealer_id,
        total_amount: order.total_amount.to_f,
        payment_method: "COD"
      }
    )
  end

  def notify_admin_order_confirmed(order)
    AdminUser.where(is_super_admin: true).find_each do |admin|
      NotificationService.deliver(
        recipient: admin,
        actor: order.buyer_dealer,
        notifiable: order,
        kind: "admin_b2b_order_confirmed",
        title: "📦 New B2B Order Confirmed",
        message: "B2B Order ##{order.id} confirmed by #{order.buyer_dealer.dealer_code}. Amount: ₹#{order.total_amount}",
        visible_in_app: true,
        delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
        payload: {
          order_id: order.id,
          buyer_dealer_id: order.buyer_dealer_id,
          seller_dealer_id: order.seller_dealer_id,
          total_amount: order.total_amount.to_f,
          payment_method: "COD"
        }
      )
    end
  end

  private

  def create_online_payment_attempt(order)
    attempt = PaymentAttempt.create!(
      buyer: order.buyer_dealer,
      status: "pending",
      amount: order.total_amount,
      currency: "INR",
      payment_gateway: "cashfree",
      result_payload: {
        checkout_context: "b2b_order",
        order_id: order.id,
        b2b_order_id: order.id
      }
    )

    cashfree = CashfreeService.new
    payload = cashfree.create_cashfree_order(
      reference: attempt.attempt_number,
      amount: attempt.amount,
      customer: order.buyer_dealer,
      return_params: { 
        payment_attempt_id: attempt.id, 
        b2b_order_id: order.id,
        attempt_number: attempt.attempt_number
      }
    )

    attempt.update!(
      gateway_order_reference: payload["cf_order_id"] || payload["order_id"],
      payment_session_id: payload["payment_session_id"],
      payment_gateway_payload: payload
    )

    {
      payment_attempt: attempt,
      payment_data: {
        payment_session_id: attempt.payment_session_id,
        gateway_order_reference: attempt.gateway_order_reference,
        payment_attempt_id: attempt.id,
        provider: "cashfree"
      }
    }
  end

  # def notify_cod_order_confirmed(order)
  #   message = <<~TEXT
  #     🎉 *Order Confirmed!*
      
  #     Order ##{order.id} has been confirmed.
  #     Buyer: #{order.buyer_dealer.dealer_code}
  #     Total: ₹#{order.total_amount}
  #     Payment Method: Cash on Delivery
  #   TEXT

  #   MetaWhatsappCloudService.new.send_text_message(
  #     to: formatted_phone_for(order.seller_dealer),
  #     body: message
  #   )

  #   message = <<~TEXT
  #     🎉 *Order Confirmed!*
      
  #     Your order has been confirmed.
  #     Seller: #{order.seller_dealer.dealer_code}
  #     Total: ₹#{order.total_amount}
  #     Payment Method: Cash on Delivery
  #   TEXT

  #   MetaWhatsappCloudService.new.send_text_message(
  #     to: formatted_phone_for(order.buyer_dealer),
  #     body: message
  #   )
  # end

  def formatted_phone_for(dealer)
    return nil if dealer.phone.blank?
    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
  end
end