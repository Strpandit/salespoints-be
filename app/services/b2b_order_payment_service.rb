class B2bOrderPaymentService
  include Rails.application.routes.url_helpers
  COD_LIMIT = 50_000.to_d
  
  def default_url_options
    { host: ENV.fetch("APP_URL", "https://api.salespoints.in") }
  end

  def initialize(order_id:, payment_method:)
    @order_id = order_id
    @payment_method = payment_method.to_s.presence || "cod"
    @order = B2bOrder.find_by(id: order_id)
  end

  def call
    raise StandardError, "Order not found" unless @order

    @order.with_lock do
      if @order.expires_at.present? && @order.expires_at <= Time.current
        raise StandardError, "Payment window has expired."
      end

      if @order.payment_status == "paid"
        raise StandardError, "Payment already completed."
      end
      
      raise StandardError, "Invalid payment method" unless B2bOrder::PAYMENT_METHODS.include?(@payment_method)
      unless @order.pending_request? || @order.pending_payment?
        raise StandardError, "Order is not in a processable state. Current status: #{@order.status}"
      end

      if @payment_method == "cod" && @order.total_amount > COD_LIMIT
        raise StandardError, "COD is not allowed for orders above ₹#{COD_LIMIT}. Please choose online payment."
      end

      if @payment_method == "cod"
        is_wholesaler = @order.is_direct_buy? && @order.source_type == "WholesalerPost"
        if is_wholesaler
          @order.update!(
            payment_method: "cod",
            payment_status: "pending"
          )
          send_order_request_to_seller(@order)
          EmailDispatcherService.b2b_request_placed(@order)
          return {
            order: @order,
            payment_method: "cod",
            status: "pending_request",
            message: "Order request sent to seller."
          }
        end
        
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
        EmailDispatcherService.b2b_payment_done(final_order)
        return { order: final_order, payment_method: "cod", status: "confirmed", message: "Order confirmed with COD." }
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
  end

  def send_payment_success_to_buyer(order)
    buyer = order.buyer_dealer
    items = order.b2b_order_items.accepted_items.to_a
    items = order.b2b_order_items.to_a if items.empty?
    first_item = items.first

    wholesaler_post = first_item&.wholesaler_post
    variant = first_item&.product_variant
    product = variant&.product || wholesaler_post&.dealer_product&.product
    
    unit_price = first_item&.unit_price
    quantity = items.sum(&:quantity)
    total_amount = order.total_amount
    phone = buyer.phone.presence || order.shipping_address&.dig("phone")

    MetaWhatsappCloudService.new.send_payment_success(
      to: formatted_phone(phone, buyer.country_code),
      product: product&.name || wholesaler_post&.title || "Product",
      variant: variant&.variant_sku || wholesaler_post&.modal_no || "Standard",
      quantity: quantity.to_s || 1,
      unit_price: unit_price.to_f.round(2).to_s || wholesaler_post&.price.to_f.round(2).to_s || 0,
      total_paid: total_amount.to_f.round(2).to_s,
      payment_id: order.payment_method.to_s.upcase,
      order_id: order.reference_number
    )
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
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
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
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
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
        delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
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
    raise StandardError, "Payment already completed." if order.payment_status == "paid"
    raise StandardError, "Payment link has expired." if order.expires_at.present? &&
                                                        order.expires_at <= Time.current
    raise StandardError, "Payment link is no longer valid." if order.status == "cancelled"
    raise StandardError, "Payment request rejected." if order.request_status == "rejected_request"
    
    existing_attempt = PaymentAttempt.lock.where(
      buyer: order.buyer_dealer,
      status: "pending"
    ).find_by("result_payload ->> 'b2b_order_id' = ?", order.id.to_s)

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

    ActiveRecord::Base.transaction do
      order.update!(
        payment_method: "online",
        payment_status: "pending"
      )
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
      
      order.update!(buyer_payment_attempt_id: attempt.id)

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
  end

  def send_order_accept_to_seller(order)
    seller = order.seller_dealer
    return if seller.blank?

    buyer = order.buyer_dealer
    
    latitude, longitude, location_name, address = get_buyer_location(buyer)

    offer = order.b2b_order_offers.find_by(dealer: order.seller_dealer, status: "accepted")
    shipped_token = offer&.shipped_token

    total_amount = order.b2b_order_items.sum(:total_price).to_f.round(2).to_s
    phone = buyer.phone.presence || order.shipping_address&.dig("phone")
    
    MetaWhatsappCloudService.new.send_order_accept(
      to: formatted_phone_for(seller),
      dealer_code: buyer.dealer_code.to_s,       
      phone: formatted_phone(phone, buyer.country_code) || "N/A",
      address: address,
      order_id: order.reference_number,
      payment_mode: order.payment_method.to_s.upcase,
      total_amount: total_amount,
      latitude: latitude,
      longitude: longitude,
      location_name: location_name,
      shipped_token: shipped_token
    )
  end

  def send_order_request_to_seller(order)
    return unless order.is_direct_buy? && order.source_type == "WholesalerPost"
    offer = order.b2b_order_offers.find_by(dealer: order.seller_dealer, status: "open")
    return unless offer
    
    item = order.b2b_order_items.first
    return unless item

    seller = order.seller_dealer
    buyer = order.buyer_dealer

    wholesaler_post = item.wholesaler_post
    variant = item.product_variant

    if wholesaler_post.present? && wholesaler_post&.dealer_product&.product_variant.present?
      variant = wholesaler_post&.dealer_product&.product_variant
    end

    product = variant&.product

    buyer_location = buyer&.dealer_location
    seller_location = seller&.dealer_location

    delivery_location = get_location(seller)
    approx_distance = if buyer_location.present? && seller_location.present? &&
                      buyer_location.latitude.present? && buyer_location.longitude.present? &&
                      seller_location.latitude.present? && seller_location.longitude.present?
    DealerLocation.distance_km(
      buyer_location.latitude.to_f,
      buyer_location.longitude.to_f,
      seller_location.latitude.to_f,
      seller_location.longitude.to_f
    ).round(2).to_s
    else
      "0"
    end

    base_url = ENV["FRONTEND_URL"] || "https://salespoints.in"
    accept_url = "#{base_url}/b2b/accept/#{offer.accept_token}"
    reject_url = "#{base_url}/b2b/reject/#{offer.reject_token}"
    image_url = get_product_image(product, variant, wholesaler_post)

    accept_token = offer.accept_token
    reject_token = offer.reject_token

    MetaWhatsappCloudService.new.send_dealer_order_request(
      to: formatted_phone_for(seller),
      product: product&.name || wholesaler_post&.title || "Product",
      variant: variant&.variant_sku || wholesaler_post&.title || "Standard",
      sku: product&.sku || wholesaler_post&.modal_no || "N/A",
      price: item.unit_price.to_f.round(2).to_s,
      quantity: item.quantity.to_s,
      total_amount: item.total_price.to_f.round(2).to_s,
      delivery_location: delivery_location,
      approx_distance: approx_distance,
      accept_token: accept_token,
      reject_token: reject_token,
      image_url: image_url
    )

    offer.update!(whatsapp_status: "sent", sent_at: Time.current)
    create_seller_request_notification(order, item)
  rescue StandardError => e
    offer&.update!(whatsapp_status: "failed", failed_at: Time.current, failure_reason: e.message)
    raise
  end

  def create_seller_request_notification(order, item)
    variant = item.product_variant
    wholesaler_post = item.wholesaler_post
    product = variant&.product || wholesaler_post&.dealer_product&.product

    product_name = product&.name || wholesaler_post&.title || "Product"
    
    NotificationService.deliver(
      recipient: order.seller_dealer,
      actor: order.buyer_dealer,
      notifiable: order,
      kind: "b2b_wholesaler_request",
      title: "📦 New Order Request",
      message: "#{order.buyer_dealer.dealer_code} wants to buy #{item.quantity} unit(s) of #{product_name}. Total: ₹#{item.total_price}",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.reference_number,
        buyer_dealer_id: order.buyer_dealer_id,
        seller_dealer_id: order.seller_dealer_id,
        total_amount: item.total_price.to_f,
        product_name: product_name,
        quantity: item.quantity
      }
    )
  end

  def get_location(dealer)
    return "Location not available" if dealer.blank?
    address = dealer.dealer_profile&.business_address
    return "Location not available" if address.blank?
    cleaned = address.to_s.strip
    if cleaned.include?(',')
      parts = cleaned.split(',').map(&:strip).reject(&:blank?)
      return parts.last(3).join(', ') if parts.size >= 3
      return parts.first if parts.size == 1
    end
    words = cleaned.split(/\s+/)
    return words.last(3).join(' ') if words.size >= 3
    return words.first if words.size == 1
    "Location not available"
  end

  def get_product_image(product, variant, wholesaler_post = nil)
    if wholesaler_post.present? && wholesaler_post.media.attached?
      attachment = wholesaler_post.media.first
      if attachment.present?
        url = rails_blob_url(attachment, only_path: false)
        return url
      end
    end

    if variant.present? && variant.media.attached?
      attachment = variant.media.first
      return rails_blob_url(attachment, only_path: false) if attachment.present?
    end
    if product.present? && product.media.attached?
      attachment = product.media.first
      return rails_blob_url(attachment, only_path: false) if attachment.present?
    end
    "#{ENV['FRONTEND_URL']}/images/ac.png"
  end

  def get_buyer_location(dealer)
    return [28.6139, 77.2090, "Default Location", "Address not available"] if dealer.blank?
    
    location = dealer.dealer_location
    profile = dealer.dealer_profile
    address = profile&.business_address.presence || "Address not available"
    
    if location.present? && location.latitude.present? && location.longitude.present?
      name = "Salespoints Dealer Point #{dealer&.dealer_code.presence || 'N/A'}"
      [location.latitude.to_f, location.longitude.to_f, name, address]
    else
      if address.present? && address != "Address not available"
        results = Geocoder.search(address)
        if results.any?
          name = "Salespoints Dealer Point #{dealer&.dealer_code.presence || 'N/A'}"
          return [results.first.latitude, results.first.longitude, name, address]
        end
      end
      [28.6139, 77.2090, "Default Location", address]
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

  def formatted_phone(phone, country_code = "+91")
    return nil if phone.blank?
    "#{country_code.presence || '+91'}#{phone}".gsub(/\s+/, "")
  end
end
