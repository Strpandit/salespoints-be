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
    raise StandardError, "No open items are available for broadcast" if open_items.empty?

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

        send_dealer_order_request_template(offer, dealer, matched_items)
        create_in_app_notification_for_seller(dealer, offer, matched_items)
        notify_admin_new_b2b_request(dealer, matched_items)
      end

      @order.update!(last_rebroadcast_at: Time.current)
    end
  end

  def send_dealer_order_request_template(offer, dealer, matched_items)
    first_item = matched_items.first
    variant = first_item&.product_variant
    product = variant&.product
    
    product_name = product&.name || "Product"
    variant_name = variant&.variant_sku || variant&.variant_attributes&.to_s || "Standard"
    sku = product&.sku || variant&.variant_sku || "N/A"
    unit_price = first_item&.unit_price || 0
    quantity = matched_items.sum(&:quantity)
    total_amount = matched_items.sum(&:total_price)

    buyer_location = @order.buyer_dealer&.dealer_location
    seller_location = dealer&.dealer_location
    
    delivery_location = get_location(dealer)
    approx_distance = if buyer_location.present? && seller_location.present?
      DealerLocation.distance_km(
        buyer_location.latitude.to_f,
        buyer_location.longitude.to_f,
        seller_location.latitude.to_f,
        seller_location.longitude.to_f
      ).round(2).to_s
    else
      "0"
    end

    base_url = ENV["FRONTEND_URL"] || "https://yourapp.com"
    accept_url = "#{base_url}/b2b/accept/#{offer.accept_token}"
    reject_url = "#{base_url}/b2b/reject/#{offer.reject_token}"

    image_url = get_product_image(product, variant)

    accept_token = offer.accept_token
    reject_token = offer.reject_token

    MetaWhatsappCloudService.new.send_dealer_order_request(
      to: formatted_phone_for(dealer),
      product: product_name,
      variant: variant_name,
      sku: sku,
      price: unit_price.to_f.round(2).to_s,
      quantity: quantity.to_s,
      total_amount: total_amount.to_f.round(2).to_s,
      delivery_location: delivery_location,
      approx_distance: approx_distance,
      accept_token: offer.accept_token,
      reject_token: offer.reject_token,
      image_url: image_url
    )

    offer.update!(whatsapp_status: "sent", sent_at: Time.current)
  rescue StandardError => e
    Rails.logger.error("Failed to send dealer_order_request template: #{e.message}")
    offer.update!(whatsapp_status: "failed", failed_at: Time.current, failure_reason: e.message)
  end

  def create_in_app_notification_for_seller(dealer, offer, matched_items)
    total_items = matched_items.sum(&:quantity)
    total_amount = matched_items.sum(&:total_price)
    first_item = matched_items.first
    product_name = first_item&.product_variant&.product&.name || "Product"

    NotificationService.deliver(
      recipient: dealer,
      actor: @actor,
      notifiable: @order,
      kind: "b2b_order_request",
      title: "📦 New B2B Request",
      message: "#{@actor.dealer_code} wants to buy #{total_items} unit(s) of #{product_name}. Total: ₹#{total_amount}",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
      payload: {
        offer_id: offer.id,
        order_id: @order.reference_number,
        buyer_dealer_id: @order.buyer_dealer_id,
        dealer_id: dealer.id,
        buyer_name: @actor.dealer_code,
        total_amount: total_amount.to_f,
        item_ids: matched_items.map(&:id),
        items: serialized_offer_items(matched_items),
        rebroadcast: false
      }
    )
  end

  def notify_admin_new_b2b_request(dealer, matched_items)
    total_items = matched_items.sum(&:quantity)
    total_amount = matched_items.sum(&:total_price)
    first_item = matched_items.first
    product_name = first_item&.product_variant&.product&.name || "Product"

    AdminUser.where(is_super_admin: true).find_each do |admin|
      NotificationService.deliver(
        recipient: admin,
        actor: @actor,
        notifiable: @order,
        kind: "admin_b2b_new_request",
        title: "📢 New B2B Request Created",
        message: "#{@actor.dealer_code} created B2B request for #{product_name} (Qty: #{total_items}). Amount: ₹#{total_amount}",
        visible_in_app: true,
        delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
        payload: {
          order_id: @order.reference_number,
          buyer_dealer_id: @order.buyer_dealer_id,
          total_amount: total_amount.to_f,
          total_items: total_items,
          product_name: product_name
        }
      )
    end
  end

  def get_product_image(product, variant)
    if variant.present? && variant.media.attached?
      attachment = variant.media.first
      return rails_blob_url(attachment, only_path: false) if attachment.present?
    end

    if product.present? && product.media.attached?
      attachment = product.media.first
      return rails_blob_url(attachment, only_path: false) if attachment.present?
    end

    if @order.source.present? && @order.source.respond_to?(:media) && @order.source.media.attached?
      attachment = @order.source.media.first
      return rails_blob_url(attachment, only_path: false) if attachment.present?
    end

    return "#{ENV['FRONTEND_URL']}/images/ac.png"
  rescue StandardError => e
    Rails.logger.error("Failed to get product image: #{e.message}")
    nil
  end

  def get_location(dealer)
    return "Location not available" if dealer.blank?
    
    address = dealer.dealer_profile&.business_address
    return "Location not available" if address.blank?
    
    cleaned = address.to_s.strip
    
    if cleaned.include?(',')
      parts = cleaned.split(',').map(&:strip).reject(&:blank?)
      return parts.last(2).join(', ') if parts.size >= 2
      return parts.first if parts.size == 1
    end
    
    words = cleaned.split(/\s+/)
    return words.last(2).join(' ') if words.size >= 2
    return words.first if words.size == 1
    
    "Location not available"
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
