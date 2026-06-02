class B2bOrderBroadcastService
  def initialize(order:, actor:)
    @order = order
    @actor = actor
  end

  def initial_broadcast!
    broadcast!(rebroadcast: false)
  end

  def rebroadcast_remaining_items!
    broadcast!(rebroadcast: true)
  end

  private

  def broadcast!(rebroadcast:)
    open_items = @order.b2b_order_items.open_items.includes(product_variant: :product).to_a
    raise StandardError, "No open B2B items are available for broadcast" if open_items.empty?

    dealer_matches = eligible_nearby_dealers(items: open_items)
    dealer_matches = dealer_matches.reject { |_dealer, items| items.empty? }
    raise StandardError, "No nearby dealers available within range" if dealer_matches.empty?

    ActiveRecord::Base.transaction do
      dealer_matches.each do |dealer, matched_items|
        item_ids = matched_items.map(&:id)
        next if open_offer_for(dealer: dealer, item_ids: item_ids).present?

        offer = B2bOrderOffer.create!(
          b2b_order: @order,
          dealer: dealer,
          status: "open",
          delivery_channel: "whatsapp",
          item_ids: item_ids,
          delivery_payload: serialized_offer_items(matched_items),
          accept_token: "b2b_accept_#{SecureRandom.hex(8)}",
          reject_token: "b2b_reject_#{SecureRandom.hex(8)}",
          recipient_phone: formatted_phone_for(dealer),
          expires_at: @order.expires_at,
          rebroadcast_count: rebroadcast ? offer_rebroadcast_count(dealer: dealer) + 1 : 0
        )

        notification = NotificationService.deliver(
          recipient: dealer,
          actor: @actor,
          notifiable: @order,
          kind: "b2b_order_request",
          title: "New B2B bulk request nearby",
          message: "A nearby dealer is requesting #{matched_items.size} item(s). Respond fast to secure what you can fulfill.",
          visible_in_app: false,
          delivery_channels: { push: true, whatsapp: true, sms: false, email: false, in_app: false },
          payload: {
            offer_id: offer.id,
            order_id: @order.id,
            buyer_dealer_id: @order.buyer_dealer_id,
            dealer_id: dealer.id,
            buyer_name: @actor.dealer_code,
            total_amount: @order.total_amount.to_f,
            requested_radius_km: @order.requested_radius_km,
            latitude: @order.latitude,
            longitude: @order.longitude,
            item_ids: item_ids,
            items: serialized_offer_items(matched_items),
            rebroadcast: rebroadcast
          }
        )
        offer.update!(notification: notification) if notification.present?
      end

      @order.update!(last_rebroadcast_at: Time.current)
    end
  end

  def open_offer_for(dealer:, item_ids:)
    @order.b2b_order_offers.open_state.find do |offer|
      offer.dealer_id == dealer.id && (offer.item_id_values & item_ids).any?
    end
  end

  def offer_rebroadcast_count(dealer:)
    @order.b2b_order_offers.where(dealer_id: dealer.id).maximum(:rebroadcast_count).to_i
  end

  def eligible_nearby_dealers(items:)
    Dealer.active
          .includes(:dealer_location, dealer_products: [:product_variant, :product])
          .where.not(id: @order.buyer_dealer_id)
          .each_with_object({}) do |dealer, matches|
      loc = dealer.dealer_location
      next unless loc&.is_active && loc.latitude.present? && loc.longitude.present?

      distance = DealerLocation.distance_km(@order.latitude, @order.longitude, loc.latitude, loc.longitude)
      next if distance > @order.requested_radius_km.to_f
      next if loc.service_radius_km.present? && distance > loc.service_radius_km.to_f

      matched_items = items.select do |item|
        dealer.dealer_products.any? do |dp|
          dp.approved? && dp.is_active && dp.stock_quantity.to_i >= item.quantity.to_i && dp.product_variant_id == item.product_variant_id
        end
      end

      matches[dealer] = matched_items if matched_items.any?
    end
  end

  def serialized_offer_items(items)
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
    return nil if dealer.phone.blank?

    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
  end
end
