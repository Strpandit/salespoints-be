class B2bOrderDealerResponseService
  include Rails.application.routes.url_helpers

  def initialize(order:, dealer:, requested_ids: nil, offer: nil)
    @order = order
    @dealer = dealer
    @requested_ids = Array(requested_ids).map(&:to_i).uniq
    @offer = offer
  end

  def accept!
    result = nil
    ActiveRecord::Base.transaction do
      if @order.is_a?(Order)
        lock_order = Order.lock.find(@order.id)
        result = accept_b2c_order!(lock_order)
      elsif @order.is_a?(B2bOrder)
        lock_order = B2bOrder.lock.find(@order.id)
        result =
          if lock_order.is_direct_buy?
            accept_direct_buy!(lock_order)
          else
            accept_b2b_broadcast!(lock_order)
          end
      else
        raise StandardError, "Invalid order type"
      end
    end

    send_accept_notifications(result)

    result
  end

  def reject!
     result = nil
    ActiveRecord::Base.transaction do
      if @order.is_a?(Order)
        lock_order = Order.lock.find(@order.id)
        result = reject_b2c_order!(lock_order)
      elsif @order.is_a?(B2bOrder)
        lock_order = B2bOrder.lock.find(@order.id)
        result = 
          if lock_order.is_direct_buy?
            reject_direct_buy!(lock_order)
          else
            reject_b2b_broadcast!(lock_order)
          end
      else
        raise StandardError, "Invalid order type"
      end
    end

    send_reject_notifications(result)

    result
  end

  private

  def accept_b2c_order!(order)
    offer = lock_b2c_request_offer!(order: order)
    ensure_b2c_order_can_be_accepted!(order)

    order.order_items.each do |item|
      deduct_b2c_stock!(item)
    end

    order.update!(
      seller_dealer_id: @dealer.id,
      status: "processing",
      status_note: "Accepted by Salespoint dealer #{@dealer.dealer_code}",
      accepted_at: Time.current
    )

    offer.update!(status: "accepted", responded_at: Time.current, whatsapp_status: "replied")
    close_other_b2c_offers!(order)

    order
  end

  def reject_b2c_order!(order)
    offer = lock_b2c_request_offer!(order: order)
    ensure_b2c_order_can_be_accepted!(order)

    offer.update!(status: "rejected", responded_at: Time.current, whatsapp_status: "replied")

    tracker = OrderBroadcastTracker.find_by(order: order, dealer: @dealer)
    tracker&.update!(status: "rejected")

    total_offers = order.order_offers.count
    rejected_offers = order.order_offers.where(status: "rejected").count

    if total_offers > 0 && total_offers == rejected_offers
      order.update!(
        status: "cancelled",
        status_note: "All sellers rejected the order"
      )
    end

    order
  end

  def lock_b2c_request_offer!(order:)
    offer = @offer.present? ? OrderOffer.lock.find(@offer.id) :
            OrderOffer.lock.find_by(order: order, dealer: @dealer, status: "open")
    
    raise StandardError, "You are not authorized to respond" unless offer
    raise StandardError, "This request has already been closed" unless offer.status == "open"
    raise StandardError, "This request has expired" if offer.expired?
    
    offer
  end

  def ensure_b2c_order_can_be_accepted!(order)
    raise StandardError, "Order request expired" if order.expires_at.present? && Time.current > order.expires_at
    raise StandardError, "Order already processed" unless order.status == "pending"
    unless order.payment_method.to_s.downcase == "cod"
      raise StandardError, "Payment not completed" unless order.payment_status == "paid"
    end
    raise StandardError, "Order already has a seller assigned" if order.seller_dealer_id.present?
  end

  def deduct_b2c_stock!(item)
    dealer_product = @dealer.dealer_products.find_by(
      product_variant_id: item.product_variant_id,
      is_active: true,
      approve_status: "approved",
      sell_in_b2c: true
    )
    
    raise StandardError, "You don't have enough stock for this item" unless dealer_product
    raise StandardError, "Insufficient stock" if dealer_product.stock_quantity < item.quantity

    dealer_product.update!(
      stock_quantity: dealer_product.stock_quantity - item.quantity
    )
    item.update!(dealer_product_id: dealer_product.id)
  end

  def close_other_b2c_offers!(order)
    order.order_offers
         .where.not(id: @offer&.id || 0)
         .where(status: "open")
         .update_all(
           status: "cancelled",
           responded_at: Time.current
         )
    
    order.order_broadcast_trackers
         .where.not(dealer_id: @dealer.id)
         .where(status: "pending")
         .update_all(status: "expired")
  end

  def send_b2c_order_accept_to_seller(order)
    seller = order.seller_dealer
    return if seller.blank?

    buyer = order.buyer
    address = order.shipping_address

    latitude, longitude, location_name = get_location_from_address(address, buyer)

    delivery_location = format_address(address)

    MetaWhatsappCloudService.new.send_order_accept(
      to: formatted_phone_for(seller),
      dealer_code: buyer.full_name.to_s,
      phone: formatted_phone_for(buyer) || "N/A",
      address: delivery_location,
      order_id: order.order_number,
      latitude: latitude.to_s,
      longitude: latitude.to_s,
      location_name: location_name
    )
  end

  def send_b2c_payment_success_to_buyer(order)
    buyer = order.buyer
    items = order.order_items
    first_item = items.first
    variant = first_item&.product_variant
    product = variant&.product

    MetaWhatsappCloudService.new.send_payment_success(
      to: formatted_phone_for(buyer),
      product: product&.name || "Product",
      variant: variant&.variant_sku || "Standard",
      quantity: items.sum(&:quantity).to_s,
      unit_price: first_item&.unit_price.to_f.round(2).to_s,
      total_paid: order.total_amount.to_f.round(2).to_s,
      payment_id: order.payment_method.to_s.upcase,
      order_id: order.order_number
    )
  end

  def create_b2c_buyer_notification(order)
    NotificationService.deliver(
      recipient: order.buyer,
      actor: order.seller_dealer,
      notifiable: order,
      kind: "b2c_order_confirmed",
      title: "✅ Order Confirmed!",
      message: "Your order ##{order.order_number} has been confirmed.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.order_number,
        seller_dealer_id: order.seller_dealer_id,
        total_amount: order.total_amount.to_f
      }
    )
  end

  def create_b2c_seller_notification(order)
    NotificationService.deliver(
      recipient: order.seller_dealer,
      actor: order.buyer,
      notifiable: order,
      kind: "b2c_order_acceptance_seller",
      title: "✅ You Accepted This Order",
      message: "You accepted order ##{order.order_number} from #{order.buyer.full_name}.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.order_number,
        buyer_id: order.buyer_id,
        total_amount: order.total_amount.to_f
      }
    )
  end

  def notify_admin_b2c_order_confirmed(order)
    AdminUser.where(is_super_admin: true).find_each do |admin|
      NotificationService.deliver(
        recipient: admin,
        actor: order.buyer,
        notifiable: order,
        kind: "admin_b2c_order_confirmed",
        title: "📦 New B2C Order Confirmed",
        message: "B2C Order ##{order.order_number} confirmed by #{order.buyer.full_name}. Amount: ₹#{order.total_amount}",
        visible_in_app: true,
        delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
        payload: {
          order_id: order.order_number,
          buyer_id: order.buyer_id,
          seller_dealer_id: order.seller_dealer_id,
          total_amount: order.total_amount.to_f
        }
      )
    end
  end

  def notify_b2c_buyer_of_rejection(order)
    buyer = order.buyer
    MetaWhatsappCloudService.new.send_text_message(
      to: formatted_phone_for(buyer),
      body: "❌ Your order ##{order.order_number} was rejected. You can try again."
    )
  end

  def accept_b2b_broadcast!(order)
    if order.accepted?
      raise StandardError, "This request has already been accepted by another dealer"
    end

    offer = lock_b2b_request_offer!(order: order)
    ensure_order_can_be_accepted!(order: order)

    open_items = order.b2b_order_items.open_items
    raise StandardError, "No open items available" if open_items.empty?

    updated_items = resolve_all_items_for_seller(open_items)
    raise StandardError, "You don't have enough stock to fulfill this order" if updated_items.blank?

    updated_items.each do |item, source, pricing|
      dealer_product_id = source.is_a?(WholesalerPost) ? source.dealer_product_id : source.id

      item.update!(
        dealer_product_id: dealer_product_id,
        status: "accepted",
        responded_at: Time.current,
        unit_price: pricing[:unit_price],
        total_price: pricing[:subtotal]
      )
    end

    order.mark_accepted!(@dealer)
    order.recalculate_totals!

    accepted_tracker = DealerBroadcastTracker.find_by!(b2b_order: order, dealer: seller)

    accepted_tracker.mark_accepted!
    DealerBroadcastTracker
      .for_order(order.id)
      .pending
      .where.not(id: accepted_tracker.id)
      .update_all(status: "expired")
    # DealerBroadcastTracker.for_order(order.id).update_all(status: "accepted")
    close_other_b2b_offers!(order)

    offer.update!(status: "accepted", responded_at: Time.current, whatsapp_status: "replied")

    order
  end

  def reject_b2b_broadcast!(order)
    offer = lock_b2b_request_offer!(order: order)

    if order.accepted?
      raise StandardError, "This request has already been accepted by another dealer"
    end

    ensure_order_can_be_accepted!(order: order)

    order.mark_rejected!

    offer.update!(
      status: "rejected",
      responded_at: Time.current,
      whatsapp_status: "replied"
    )

    tracker = DealerBroadcastTracker.find_by(b2b_order: order, dealer: @dealer)
    tracker&.update!(status: "rejected")

    total_dealers = DealerBroadcastTracker.for_order(order.id).count
    rejected_count = DealerBroadcastTracker.for_order(order.id).where(status: "rejected").count
    
    if total_dealers > 0 && total_dealers == rejected_count
      order.update!(
        request_status: "rejected_request",
        status: "cancelled",
        rejected_at: Time.current
      )

      close_other_b2b_offers!(order)
    end

    order
  end

  def accept_direct_buy!(order)
    offer = lock_b2b_request_offer!(order: order)
    ensure_order_can_be_accepted!(order: order)
    raise StandardError, "Order is not in pending request" unless order.pending_request?

    order = B2bOrder.lock.find(order.id)

    order.b2b_order_items.each do |item|
      deduct_b2b_stock!(item)

      item.update!(
        status: "accepted",
        responded_at: Time.current
      )
    end

    order.update!(
      status: "confirmed",
      request_status: "accepted_request",
      confirmed_at: Time.current,
      accepted_at: Time.current
    )

    offer.reload
    offer.update!(status: "accepted", responded_at: Time.current, whatsapp_status: "replied")
    close_other_b2b_offers!(order)

    order.reload

    order
  end

  def reject_direct_buy!(order)
    offer = lock_b2b_request_offer!(order: order)
    ensure_order_can_be_accepted!(order: order)

    raise StandardError, "Order is not in pending request state" unless order.pending_request?
    order.update!(status: "cancelled", request_status: "rejected_request", rejected_at: Time.current)
    offer.update!(status: "rejected", responded_at: Time.current, whatsapp_status: "replied")

    # refund code here
    order
  end

  def lock_b2b_request_offer!(order:)
    offer = @offer.present? ? B2bOrderOffer.lock.find(@offer.id) :
            B2bOrderOffer.lock.find_by(b2b_order: order, dealer: @dealer, status: "open")

    raise StandardError, "You are not authorized to respond" unless offer
    raise StandardError, "This request has already been closed" unless offer.status == "open"
    raise StandardError, "This request has expired" if offer.expired?

    offer
  end

  def ensure_order_can_be_accepted!(order:)
    raise StandardError, "Order request expired" if order.expires_at.present? && Time.current > order.expires_at
    raise StandardError, "Cannot respond to your own request" if order.buyer_dealer_id == @dealer.id
    raise StandardError, "Order already processed" unless order.pending_request?
  end

  def resolve_all_items_for_seller(items_scope)
    resolved = []

    items_scope.each do |item|
      if item.wholesaler_post_id.present?
        wholesaler_post = WholesalerPost.lock.find(item.wholesaler_post_id)
        dealer_product = wholesaler_post.dealer_product

        unless dealer_product
          Rails.logger.warn "Dealer product missing for wholesaler post #{wholesaler_post.id}"
          return nil
        end

        unless dealer_product&.sellable_in_b2b?
          Rails.logger.warn "Dealer product #{wholesaler_post.dealer_product_id} is not enabled for B2B sale"
          return nil
        end

        unless wholesaler_post.stock_quantity.to_i >= item.quantity.to_i
          Rails.logger.warn "Wholesaler post #{wholesaler_post.id} has insufficient stock"
          return nil
        end

        pricing = Pricing::PriceCalculator.new(
          variant: dealer_product.product_variant,
          quantity: item.quantity,
          user_type: :dealer
        ).call

        resolved << [item, wholesaler_post, pricing]
      else
        dealer_product = @dealer.dealer_products.live.for_b2b.find_by(
          product_variant_id: item.product_variant_id
        )

        unless dealer_product
          Rails.logger.warn "Dealer #{@dealer.id} doesn't have product variant #{item.product_variant_id}"
          return nil
        end

        unless dealer_product.stock_quantity.to_i >= item.quantity.to_i
          Rails.logger.warn "Dealer #{@dealer.id} doesn't have enough stock for variant #{item.product_variant_id}"
          return nil
        end

        item.update!(
          dealer_product_id: dealer_product.id
        )

        pricing = Pricing::PriceCalculator.new(
          variant: dealer_product.product_variant,
          quantity: item.quantity,
          user_type: :dealer
        ).call

        resolved << [item, dealer_product, pricing]
      end
    end

    resolved
  end

  def close_other_b2b_offers!(order)
    order.b2b_order_offers
         .where.not(id: @offer&.id || 0)
         .where(status: "open")
         .update_all(
           status: "cancelled",
           responded_at: Time.current
         )
  end

  def send_payment_request_template(order)
    buyer = order.buyer_dealer
    items = order.b2b_order_items.accepted_items
    first_item = items.first
    variant = first_item&.product_variant
    product = variant&.product
    
    payment_url = "#{order.payment_token}"
    
    MetaWhatsappCloudService.new.send_payment_request(
      to: formatted_phone_for(buyer),
      product: product&.name || "Product",
      variant: variant&.variant_sku || "Standard",
      unit_price: first_item&.unit_price.to_f.round(2).to_s,
      quantity: items.sum(&:quantity).to_s,
      total_amount: order.total_amount.to_f.round(2).to_s,
      payment_url: payment_url
    )

    order.update!(payment_link_sent_at: Time.current)
  end

  def create_buyer_notification(order, status)
    buyer = order.buyer_dealer
    
    if status == "accepted"
      title = "✅ Request Accepted!"
      message = "Your request has been accepted. Please complete payment."
      kind = "b2b_order_accepted"
    else
      title = "❌ Request Rejected"
      message = "Your request has been rejected."
      kind = "b2b_order_rejected"
    end

    NotificationService.deliver(
      recipient: buyer,
      actor: @dealer,
      notifiable: order,
      kind: kind,
      title: title,
      message: message,
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.reference_number,
        dealer_id: @dealer.id,
        status: status,
        total_amount: order.total_amount.to_f
      }
    )
  end

  def create_seller_acceptance_notification(order)
    NotificationService.deliver(
      recipient: @dealer,
      actor: @dealer,
      notifiable: order,
      kind: "b2b_order_acceptance_confirmation",
      title: "✅ You Accepted This Request",
      message: "You have accepted the request from #{order.buyer_dealer.dealer_code}. Waiting for buyer to complete payment.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.reference_number,
        buyer_dealer_id: order.buyer_dealer_id,
        total_amount: order.total_amount.to_f
      }
    )
  end

  def notify_buyer_of_rejection(order)
    buyer = order.buyer_dealer

    message = <<~TEXT
      ❌ *Request Rejected*

      Your request has been rejected.

      You can try with other sellers.
    TEXT

    MetaWhatsappCloudService.new.send_text_message(
      to: formatted_phone_for(buyer),
      body: message
    )
  end

  def send_payment_success_to_buyer(order)
    B2bOrderPaymentService.new(order_id: order.id, payment_method: order.payment_method)
                          .send(:send_payment_success_to_buyer, order)
  end

  def send_order_accept_to_seller(order)
    seller = order.seller_dealer
    return if seller.blank?

    buyer = order.buyer_dealer
    latitude, longitude, location_name, address = get_buyer_location(buyer)
    
    MetaWhatsappCloudService.new.send_order_accept(
      to: formatted_phone_for(seller),
      dealer_code: buyer.dealer_code.to_s,
      phone: formatted_phone_for(buyer) || "N/A",
      address: address,
      order_id: order.reference_number,
      latitude: latitude,
      longitude: longitude,
      location_name: location_name
    )
  end

  def create_buyer_acceptance_notification(order)
    NotificationService.deliver(
      recipient: order.buyer_dealer,
      actor: order.seller_dealer,
      notifiable: order,
      kind: "b2b_order_accepted_buyer",
      title: "✅ Order Accepted!",
      message: "Your order #{order.reference_number} has been accepted. Amount: ₹#{order.total_amount}",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.reference_number,
        seller_dealer_id: order.seller_dealer_id,
        total_amount: order.total_amount.to_f
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

  def formatted_phone_for(dealer)
    return nil if dealer.phone.blank?
    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
  end

  def deduct_b2b_stock!(item)
    if item.wholesaler_post_id.present?
      wholesaler_post = WholesalerPost.lock.find(item.wholesaler_post_id)
      if wholesaler_post.stock_quantity.to_i < item.quantity.to_i
        raise StandardError, "Insufficient stock for wholesaler post #{wholesaler_post.id}"
      end
      wholesaler_post.update!(
        stock_quantity: wholesaler_post.stock_quantity - item.quantity
      )
    elsif item.dealer_product_id.present?
      dealer_product = DealerProduct.lock.find(item.dealer_product_id)
      if dealer_product.stock_quantity.to_i < item.quantity.to_i
        raise StandardError, "Insufficient stock for dealer product #{dealer_product.id}"
      end
      dealer_product.update!(
        stock_quantity: dealer_product.stock_quantity - item.quantity
      )
    else
      raise StandardError, "Cannot deduct stock: no source found for item #{item.id}"
    end
    
    item
  end

  def get_location_from_address(address, buyer)
    if address.present?
      if address["latitude"].present? && address["longitude"].present?
        return [
          address["latitude"].to_s,
          address["longitude"].to_s,
          "Customer Location - #{format_address(address)}"
        ]
      end

      pincode = address["postal_code"] || address[:postal_code]
      if pincode.present?
        coords = B2bPincodeAvailabilityService.geocode_pincode(pincode)
        if coords.present?
          return [
            coords[:latitude].to_s,
            coords[:longitude].to_s,
            "Customer Location - #{format_address(address)}"
          ]
        end
      end

      full_address = [
        address["address_line1"],
        address["city"],
        address["state"],
        address["postal_code"]
      ].compact.join(", ")

      if full_address.present?
        results = Geocoder.search(full_address)
        if results.any?
          return [
            results.first.latitude.to_s,
            results.first.longitude.to_s,
            "Customer Location - #{full_address}"
          ]
        end
      end
    end

    if buyer.respond_to?(:addresses)
      default_address = buyer.addresses.find_by(is_default: true)
      if default_address.present?
        pincode = default_address.postal_code
        if pincode.present?
          coords = B2bPincodeAvailabilityService.geocode_pincode(pincode)
          if coords.present?
            return [
              coords[:latitude].to_s,
              coords[:longitude].to_s,
              "Customer Location - #{default_address.full_address}"
            ]
          end
        end
        
        full_address = default_address.full_address
        if full_address.present?
          results = Geocoder.search(full_address)
          if results.any?
            return [
              results.first.latitude.to_s,
              results.first.longitude.to_s,
              "Customer Location - #{full_address}"
            ]
          end
        end
      end
    end

    ["28.6139", "77.2090", "Customer Location"]
  end

  def format_address(address)
    return "Address not available" if address.blank?
    
    if address.is_a?(Hash) || address.is_a?(ActionController::Parameters)
      parts = []
      parts << address["address_line1"] if address["address_line1"].present?
      parts << address["address_line2"] if address["address_line2"].present?
      parts << address["city"] if address["city"].present?
      parts << address["state"] if address["state"].present?
      parts << address["postal_code"] if address["postal_code"].present?
      parts << address["country"] if address["country"].present?
      return parts.compact.join(", ") if parts.any?
    end
    
    address.to_s
  end

  def send_accept_notifications(order)
    return unless order

    if order.is_a?(Order)

      send_b2c_order_accept_to_seller(order)
      send_b2c_payment_success_to_buyer(order)
      create_b2c_buyer_notification(order)
      create_b2c_seller_notification(order)
      notify_admin_b2c_order_confirmed(order)
      EmailDispatcherService.retail_order_accepted(order)

    elsif order.is_a?(B2bOrder)

      if order.is_direct_buy?

        send_order_accept_to_seller(order)
        send_payment_success_to_buyer(order)
        create_seller_acceptance_notification(order)
        create_buyer_acceptance_notification(order)
        notify_admin_order_confirmed(order)
        EmailDispatcherService.b2b_request_accepted(order)

      else

        send_payment_request_template(order)
        create_buyer_notification(order, "accepted")
        create_seller_acceptance_notification(order)
        EmailDispatcherService.b2b_request_accepted(order)

      end
    end
  end

  def send_reject_notifications(order)
    return unless order

    if order.is_a?(Order)

      notify_buyer_of_rejection(order)
      create_buyer_notification(order, "rejected")
      EmailDispatcherService.retail_order_terminated(order, "rejected")

    elsif order.is_a?(B2bOrder)

      notify_buyer_of_rejection(order)
      create_buyer_notification(order, "rejected")
      EmailDispatcherService.b2b_order_terminated(order, "rejected")

    end
  end
end
