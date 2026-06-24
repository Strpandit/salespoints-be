class B2bOrderDealerResponseService
  def initialize(order:, dealer:, requested_ids: nil, offer: nil)
    @order = order
    @dealer = dealer
    @requested_ids = Array(requested_ids).map(&:to_i).uniq
    @offer = offer
  end

  def accept!
    ActiveRecord::Base.transaction do
      lock_order = B2bOrder.lock.includes(:buyer_dealer, b2b_order_items: [:product_variant, { dealer_product: :dealer }]).find(@order.id)
      offer = lock_b2b_request_offer!(order: lock_order)

      ensure_order_can_be_processed!(order: lock_order)

      visible_item_ids = offer.item_id_values
      candidate_ids = @requested_ids.present? ? (visible_item_ids & @requested_ids) : visible_item_ids
      raise StandardError, "No matching open items are available for this request" if candidate_ids.empty?

      candidate_items = lock_order.b2b_order_items.open_items.where(id: candidate_ids)
      updated_items = resolve_order_items_for_seller(candidate_items)
      raise StandardError, "You don't have enough stock for the selected items" if updated_items.blank?

      updated_items.map { |item, dealer_product, pricing| item.id }
        item.update!(
          dealer_product_id: dealer_product.id,
          status: "accepted",
          responded_at: Time.current,
          unit_price: pricing[:unit_price],
          total_price: pricing[:subtotal]
        )
      end

      lock_order.update!(seller_dealer_id: @dealer.id) if lock_order.seller_dealer_id.blank?
      lock_order.recalculate_totals!
      lock_order.refresh_status!

      updated_items.each do |item, dealer_product, pricing|
        dealer_product.reload
        dealer_product.update!(stock_quantity: dealer_product.stock_quantity.to_i - item.quantity.to_i)
      end

      offer.update!(status: "accepted", responded_at: Time.current, whatsapp_status: "replied")
      mark_offers_after_acceptance!(order: lock_order, accepted_items: updated_items.map(&:first))
      notify_buyer_of_acceptance!(order: lock_order, updated_items: updated_items)
      notify_seller_of_buyer_details!(order: lock_order, updated_items: updated_items)

      updated_items.map(&:first)
    end
  end

  def reject!
    ActiveRecord::Base.transaction do
      lock_order = B2bOrder.lock.includes(:buyer_dealer, b2b_order_items: :product_variant).find(@order.id)
      offer = lock_b2b_request_offer!(order: lock_order)

      ensure_order_can_be_processed!(order: lock_order)

      visible_item_ids = offer.item_id_values
      rejected_ids = @requested_ids.present? ? (visible_item_ids & @requested_ids) : visible_item_ids
      raise StandardError, "No matching open items are available for this request" if rejected_ids.empty?

      remaining_ids = visible_item_ids - rejected_ids
      offer.update!(
        status: remaining_ids.empty? ? "rejected" : "open",
        item_ids: remaining_ids,
        delivery_payload: serialize_b2b_items(lock_order.b2b_order_items.where(id: remaining_ids)),
        responded_at: Time.current,
        whatsapp_status: "replied"
      )

      rejected_ids.length
    end
  end

  private

  def lock_b2b_request_offer!(order:)
    offer = @offer.present? ? B2bOrderOffer.lock.find(@offer.id) : B2bOrderOffer.lock.find_by(b2b_order: order, dealer: @dealer, status: "open")
    raise StandardError, "You are not allowed to respond to this order" unless offer
    raise StandardError, "This request has already been closed for you" unless offer.status == "open"
    raise StandardError, "This request has expired" if offer.expired?
    raise StandardError, "No items are pending for your response" if offer.item_id_values.empty?

    offer
  end

  def ensure_order_can_be_processed!(order:)
    raise StandardError, "Order request expired" if order.expires_at.present? && Time.current > order.expires_at
    raise StandardError, "Cannot respond to your own request" if order.buyer_dealer_id == @dealer.id
    raise StandardError, "Order request not found or already processed" unless %w[pending partially_accepted].include?(order.status)
  end

  def resolve_order_items_for_seller(items_scope)
    resolved = []

    items_scope.each do |item|
      dealer_product = @dealer.dealer_products.live.find_by(product_variant_id: item.product_variant_id)
      return nil if dealer_product.blank?
      return nil if dealer_product.stock_quantity.to_i < item.quantity.to_i

      pricing = Pricing::PriceCalculator.new(
        variant: dealer_product.product_variant,
        quantity: item.quantity,
        user_type: :dealer
      ).call

      resolved << [item, dealer_product, pricing]
    end

    resolved
  end

  def mark_offers_after_acceptance!(order:, accepted_items:)
    pending_item_ids = order.b2b_order_items.open_items.pluck(:id)

    order.b2b_order_offers.find_each do |entry|
      remaining_for_recipient = entry.item_id_values & pending_item_ids

      next_state =
        if entry.dealer_id == @dealer.id
          "accepted"
        elsif entry.status == "rejected"
          "rejected"
        elsif remaining_for_recipient.empty?
          "cancelled"
        else
          "open"
        end

      entry.update!(
        status: next_state,
        item_ids: remaining_for_recipient,
        delivery_payload: serialize_b2b_items(order.b2b_order_items.where(id: remaining_for_recipient)),
        responded_at: (entry.dealer_id == @dealer.id ? Time.current : entry.responded_at)
      )
    end
  end

  def notify_buyer_of_acceptance!(order:, updated_items:)
    buyer = order.buyer_dealer

    NotificationService.deliver(
      recipient: buyer,
      actor: @dealer,
      notifiable: order,
      kind: "b2b_order_accepted",
      title: "Dealer accepted your B2B request",
      message: "#{@dealer.dealer_code} accepted #{updated_items.size} item(s) from your request.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.id,
        seller_dealer_id: @dealer.id,
        seller_name: @dealer.dealer_code,
        accepted_item_ids: updated_items.map { |item, _dealer_product, _price| item.id },
        accepted_items: serialize_b2b_items(updated_items.map(&:first)),
        b2b_state: order.status
      }
    )

    B2bOrderMailer.acceptance_update(order.id, @dealer.id, updated_items.map { |item, _dealer_product, _price| item.id }).deliver_later if buyer.email.present?
  end

  def notify_seller_of_buyer_details!(order:, updated_items:)
    buyer = order.buyer_dealer
    accepted_items = updated_items.map(&:first)
    item_lines = accepted_items.map do |item|
      item_name = item.product_variant&.product&.name || item.product_variant&.variant_sku || "Item"
      unit_price = item.unit_price.to_f.round(2)
      "#{item_name} x #{item.quantity} @ Rs #{unit_price}"
    end.join("\n")

    buyer_message = <<~TEXT.strip
      Buyer details for B2B request ##{order.id}

      Accepted items:
      #{item_lines}

      Buyer dealer code: #{buyer&.dealer_code || "N/A"}
      Mobile: #{formatted_phone_for(buyer)}
      Address: #{buyer&.dealer_profile&.business_address.presence || "N/A"}
    TEXT

    NotificationService.deliver(
      recipient: @dealer,
      actor: buyer,
      notifiable: order,
      kind: "b2b_order_buyer_details",
      title: "Buyer details shared",
      message: buyer_message,
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: true, sms: false, email: false, in_app: true },
      payload: {
        order_id: order.id,
        buyer_dealer_id: buyer&.id,
        buyer_code: buyer&.dealer_code,
        buyer_phone: formatted_phone_for(buyer),
        buyer_address: buyer&.dealer_profile&.business_address,
        accepted_item_ids: accepted_items.map(&:id)
      }
    )
  end

  def serialize_b2b_items(items)
    Array(items).map do |item|
      {
        id: item.id,
        product_variant_id: item.product_variant_id,
        product_name: item.product_variant&.product&.name,
        variant_sku: item.product_variant&.variant_sku,
        quantity: item.quantity,
        unit_price: item.unit_price.to_f,
        total_price: item.total_price.to_f,
        status: item.status
      }
    end
  end

  def formatted_phone_for(dealer)
    return "N/A" if dealer.blank? || dealer.phone.blank?

    country_code = dealer.country_code.presence || "+91"
    "#{country_code} #{dealer.phone}"
  end
end
