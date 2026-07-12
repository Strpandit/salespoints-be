class B2bOrderDealerResponseService
  def initialize(order:, dealer:, requested_ids: nil, offer: nil)
    @order = order
    @dealer = dealer
    @requested_ids = Array(requested_ids).map(&:to_i).uniq
    @offer = offer
  end

  def accept!
    ActiveRecord::Base.transaction do
      lock_order = B2bOrder.lock.find(@order.id)

      if lock_order.is_direct_buy?
        accept_direct_buy!(lock_order)
      else
        if lock_order.accepted?
          raise StandardError, "This request has already been accepted by another dealer"
        end

        offer = lock_b2b_request_offer!(order: lock_order)
        ensure_order_can_be_accepted!(order: lock_order)

        open_items = lock_order.b2b_order_items.open_items
        raise StandardError, "No open items available" if open_items.empty?

        updated_items = resolve_all_items_for_seller(open_items)
        raise StandardError, "You don't have enough stock to fulfill this order" if updated_items.blank?

        updated_items.each do |item, source, pricing|
          dealer_product_id =
            if source.is_a?(WholesalerPost)
              source.dealer_product_id
            else
              source.id
            end

          item.update!(
            dealer_product_id: dealer_product_id,
            status: "accepted",
            responded_at: Time.current,
            unit_price: pricing[:unit_price],
            total_price: pricing[:subtotal]
          )

        end

        lock_order.mark_accepted!(@dealer)
        lock_order.recalculate_totals!

        DealerBroadcastTracker.for_order(lock_order.id).update_all(status: "accepted")
        close_other_offers!(lock_order)

        offer.update!(status: "accepted", responded_at: Time.current, whatsapp_status: "replied")

        send_payment_request_template(lock_order)
        create_buyer_notification(lock_order, "accepted")
        create_seller_acceptance_notification(lock_order)

        updated_items.map(&:first)
      end
    end
  end

  def reject!
    ActiveRecord::Base.transaction do
      lock_order = B2bOrder.lock.find(@order.id)

      if lock_order.is_direct_buy?
        reject_direct_buy!(lock_order)
      else
        offer = lock_b2b_request_offer!(order: lock_order)

        if lock_order.accepted?
          raise StandardError, "This request has already been accepted by another dealer"
        end

        ensure_order_can_be_accepted!(order: lock_order)

        lock_order.mark_rejected!

        offer.update!(
          status: "rejected",
          responded_at: Time.current,
          whatsapp_status: "replied"
        )

        tracker = DealerBroadcastTracker.find_by(b2b_order: lock_order, dealer: @dealer)
        tracker&.update!(status: "rejected")

        close_other_offers!(lock_order)

        notify_buyer_of_rejection(lock_order)
        create_buyer_notification(lock_order, "rejected")

        total_dealers = DealerBroadcastTracker.for_order(lock_order.id).count
        rejected_count = DealerBroadcastTracker.for_order(lock_order.id).where(status: "rejected").count
        
        if total_dealers > 0 && total_dealers == rejected_count
          lock_order.update!(
            request_status: "rejected_request",
            status: "cancelled",
            rejected_at: Time.current
          )
        end
      end
    end
  end

  private

  def accept_direct_buy!(order)
    offer = lock_b2b_request_offer!(order: order)
    ensure_order_can_be_accepted!(order: order)
    raise StandardError, "Order is not in pending request" unless order.status == "pending_request"

    order.b2b_order_items.each do |item|
      deduct_stock!(item)
    end

    order.update!(
      status: "confirmed",
      request_status: "accepted_request",
      confirmed_at: Time.current
    )

    offer.update!(status: "accepted", responded_at: Time.current, whatsapp_status: "replied")
    close_other_offers!(order)

    send_payment_success_to_buyer(order)
    create_seller_acceptance_notification(order)
  end

  def reject_direct_buy!(order)
    offer = lock_b2b_request_offer!(order: order)
    ensure_order_can_be_accepted!(order: order)

    raise StandardError, "Order is not in pending_request state" unless order.status == "pending_request"
    order.update!(status: "cancelled", rejected_at: Time.current)
    offer.update!(status: "rejected", responded_at: Time.current, whatsapp_status: "replied")

    notify_buyer_of_rejection(order)
    # (वैकल्पिक) रिफंड इनिशियेट करें
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

        unless wholesaler_post.stock_quantity.to_i >= item.quantity.to_i
          Rails.logger.warn "Wholesaler post #{wholesaler_post.id} has insufficient stock"
          return nil
        end

        pricing = Pricing::PriceCalculator.new(
          variant: wholesaler_post.dealer_product.product_variant,
          quantity: item.quantity,
          user_type: :dealer
        ).call

        resolved << [item, wholesaler_post, pricing]
      else
        dealer_product = @dealer.dealer_products.live.find_by(
          product_variant_id: item.product_variant_id
        )

        unless dealer_product && dealer_product.stock_quantity.to_i >= item.quantity.to_i
          Rails.logger.warn "Dealer #{@dealer.id} doesn't have enough stock for variant #{item.product_variant_id}"
          return nil
        end

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

  def close_other_offers!(order)
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
      variant: variant&.variant_attributes&.to_s || variant&.variant_sku || "Standard",
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
      message = "#{@dealer.dealer_code} has accepted your request. Please complete payment."
      kind = "b2b_order_accepted"
    else
      title = "❌ Request Rejected"
      message = "#{@dealer.dealer_code} has rejected your request."
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
      delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
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
      delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
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

      #{@dealer.dealer_code} has rejected your request.

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

  def formatted_phone_for(dealer)
    return nil if dealer.phone.blank?
    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
  end
end
