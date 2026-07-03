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
      final_order = B2bOrderCreationService.new(
        request_order: @order,
        payment_method: "cod",
        payment_status: "pending"
      ).call

      send_order_accept_to_seller(final_order)
      send_payment_success_to_buyer(final_order)
      create_buyer_payment_success_notification(final_order)
      create_seller_payment_success_notification(final_order)
      notify_admin_order_confirmed(final_order)
      return { order: final_order, payment_method: "cod", status: "confirmed", message: "Order confirmed with COD" }
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
      payment_id: order.payment_method.to_s.upcase,
      order_id: order.reference_number,
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
      message: "Your order ##{order.reference_number} has been confirmed with #{order.payment_method.to_s.upcase}.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
      payload: {
        order_id: order.reference_number,
        total_amount: order.total_amount.to_f,
        payment_method: order.payment_method.to_s.upcase
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
      message: "Buyer #{order.buyer_dealer.dealer_code} has confirmed #{order.payment_method.to_s.upcase} for order ##{order.reference_number}.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
      payload: {
        order_id: order.reference_number,
        buyer_dealer_id: order.buyer_dealer_id,
        total_amount: order.total_amount.to_f,
        payment_method: order.payment_method.to_s.upcase
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
        message: "B2B Order ##{order.reference_number} confirmed by #{order.buyer_dealer.dealer_code}. Amount: ₹#{order.total_amount}",
        visible_in_app: true,
        delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
        payload: {
          order_id: order.reference_number,
          buyer_dealer_id: order.buyer_dealer_id,
          seller_dealer_id: order.seller_dealer_id,
          total_amount: order.total_amount.to_f,
          payment_method: order.payment_method.to_s.upcase
        }
      )
    end
  end

  private

  def create_online_payment_attempt(order)
    existing_attempt = PaymentAttempt.find_by(
      buyer: order.buyer_dealer,
      status: "pending"
    )

    if existing_attempt.present? &&
      existing_attempt.result_payload["b2b_order_id"] == order.id

      return {
        payment_attempt: existing_attempt,
        payment_data: {
          payment_session_id: existing_attempt.payment_session_id,
          gateway_order_reference: existing_attempt.gateway_order_reference,
          payment_attempt_id: existing_attempt.id,
          provider: "cashfree"
        }
      }
    end

    attempt = PaymentAttempt.create!(
      buyer: order.buyer_dealer,
      status: "pending",
      amount: order.total_amount,
      currency: "INR",
      payment_gateway: "cashfree",
      result_payload: {
        checkout_context: "b2b_order",
        order_id: order.id,
        b2b_order_id: order.id,
        request_metadata: {
          request_order_id: order.id,
          latitude: order.latitude,
          longitude: order.longitude,
          radius_km: order.requested_radius_km
        }
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

  def send_order_accept_to_seller(order)
    seller = order.seller_dealer
    return if seller.blank?

    buyer = order.buyer_dealer
    
    latitude, longitude, location_name = get_buyer_location(buyer)
    
    MetaWhatsappCloudService.new.send_order_accept(
      to: formatted_phone_for(seller),
      dealer_code: buyer.dealer_code.to_s,       
      phone: formatted_phone_for(buyer) || "N/A",
      address: get_address(buyer),               
      order_id: order.reference_number,
      latitude: latitude,
      longitude: longitude,
      location_name: location_name
    )
  end

  def get_buyer_location(dealer)
    return [28.6139, 77.2090, "Default Location"] if dealer.blank?
    
    location = dealer.dealer_location
    
    if location.present? && location.latitude.present? && location.longitude.present?
      name = dealer.dealer_profile&.business_name.presence || "Dealer Location"
      [location.latitude.to_f, location.longitude.to_f, name]
    else
      address = get_address(dealer)
      if address.present? && address != "Address not available"
        results = Geocoder.search(address)
        if results.any?
          name = dealer.dealer_profile&.business_name.presence || "Dealer Location"
          return [results.first.latitude, results.first.longitude, name]
        end
      end
      [28.6139, 77.2090, "Default Location"]
    end
  end

  def get_address(dealer)
    return "Address not available" if dealer.blank?
    
    profile = dealer.dealer_profile
    return "Address not available" if profile.blank?
    
    profile.business_address.presence || "Address not available"
  end

  def formatted_phone_for(dealer)
    return nil if dealer.phone.blank?
    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
  end
end
