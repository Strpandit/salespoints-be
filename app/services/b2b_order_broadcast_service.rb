class B2bOrderBroadcastService
  include Rails.application.routes.url_helpers
  DEFAULT_RADIUS = 10
  MAX_RADIUS = 30
  INCREMENT_PER_MINUTE = 2

  def initialize(order:, actor:, current_radius: nil, is_b2c: false)
    @order = order
    @actor = actor
    @current_radius = current_radius || order.current_broadcast_radius || DEFAULT_RADIUS
    @is_b2c = is_b2c
  end

  def initial_broadcast!
    broadcast!(is_initial: true)
  end

  def incremental_broadcast!
    return if @is_b2c

    return if @order.expired? if @order.respond_to?(:expired?)
    return if @order.accepted? if @order.respond_to?(:accepted?)

    @current_radius += INCREMENT_PER_MINUTE
    return expire_order! if @current_radius > MAX_RADIUS

    @order.update!(
      current_broadcast_radius: @current_radius,
      last_rebroadcast_at: Time.current,
      broadcast_attempts: @order.broadcast_attempts + 1
    )

    broadcast!(is_initial: false)

    schedule_next_broadcast if !@order.expired? && !@order.accepted?
  end

  private

  def broadcast!(is_initial:)
    items = @order.b2b_order_items.open_items.includes(product_variant: :product).to_a
    return if items.empty?

    eligible_dealers = find_eligible_dealers(items)
    already_broadcasted = DealerBroadcastTracker.for_order(@order.id).pluck(:dealer_id)
    new_dealers = eligible_dealers.reject { |dealer, _| already_broadcasted.include?(dealer.id) }

    return if new_dealers.empty?

    ActiveRecord::Base.transaction do
      new_dealers.each do |dealer, matched_items|
        DealerBroadcastTracker.create!(
          b2b_order: @order,
          dealer: dealer,
          broadcast_radius_km: @current_radius,
          attempt_count: is_initial ? 1 : @order.broadcast_attempts + 1,
          last_broadcast_at: Time.current,
          status: "pending"
        )

        offer = B2bOrderOffer.find_or_initialize_by(b2b_order: @order, dealer: dealer)

        if offer.new_record?
          offer.assign_attributes(
            status: "open",
            delivery_channel: "whatsapp",
            item_ids: matched_items.map(&:id),
            delivery_payload: serialized_offer_items(matched_items),
            accept_token: "b2b_accept_#{SecureRandom.hex(8)}",
            reject_token: "b2b_reject_#{SecureRandom.hex(8)}",
            recipient_phone: formatted_phone_for(dealer),
            expires_at: @order.respond_to?(:expires_at) ? @order.expires_at : 4.hours.from_now,
            whatsapp_status: "pending",
            rebroadcast_count: 0
          )
          offer.save!
        end

        send_dealer_order_request_template(offer, dealer, matched_items)
        create_in_app_notification_for_seller(dealer, offer, matched_items)
        notify_admin_new_b2b_request(dealer, matched_items)
      end
    end
    EmailDispatcherService.b2b_request_placed(@order)
  end

  def find_eligible_dealers(items)
    buyer_lat = @order.latitude.to_f
    buyer_lng = @order.longitude.to_f

    matches = {}

    items.each do |item|
      next if item.product_variant_id.blank?

      DealerProduct.live
                  .for_b2b
                  .includes(:product_variant, dealer: :dealer_location)
                  .where(product_variant_id: item.product_variant_id)
                  .where("stock_quantity >= ?", item.quantity)
                  .find_each do |dealer_product|

        dealer = dealer_product.dealer
        next unless dealer.status == "active"
        next if dealer.id == @order.buyer_dealer_id

        location = dealer.dealer_location
        next unless location&.is_active?
        next if location.latitude.blank? || location.longitude.blank?

        distance_info = GoogleMapsService.instance.driving_distance(
          buyer_lat,
          buyer_lng,
          location.latitude.to_f,
          location.longitude.to_f
        )

        distance = if distance_info.present?
          distance_info[:distance_km]
        else
          DealerLocation.distance_km(
            buyer_lat,
            buyer_lng,
            location.latitude,
            location.longitude
          )
        end

        next if distance > @current_radius

        seller_radius = location.service_radius_km.to_f
        next if seller_radius.positive? && distance > seller_radius

        matches[dealer] ||= []
        matches[dealer] << item unless matches[dealer].include?(item)
      end
    end

    matches
  end

  def schedule_next_broadcast
    return if @is_b2c
    return if @current_radius >= MAX_RADIUS
    
    BroadcastB2bOrderJob.set(wait: 1.minute).perform_later(@order.id)
  end

  def send_dealer_order_request_template(offer, dealer, matched_items)
    first_item = matched_items.first
    variant = first_item&.product_variant
    product = variant&.product
    
    product_name = product&.name || "Product"
    variant_name = variant&.variant_sku || "Standard"
    sku = product&.sku || variant&.variant_sku || "N/A"
    unit_price = first_item&.unit_price || 0
    quantity = matched_items.sum(&:quantity)
    total_amount = matched_items.sum(&:total_price)

    buyer_location = @order.buyer_dealer&.dealer_location
    seller_location = dealer&.dealer_location
    
    delivery_location = get_location(dealer)
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

    image_url = get_product_image(product, variant)

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
      title: "📦 New Order Request",
      message: "#{@actor.dealer_code} wants to buy #{total_items} unit(s) of #{product_name}. Total: ₹#{total_amount}",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        offer_id: offer.id,
        order_id: @order.reference_number,
        buyer_dealer_id: @order.buyer_dealer_id,
        dealer_id: dealer.id,
        buyer_name: @actor.dealer_code,
        total_amount: total_amount.to_f,
        item_ids: matched_items.map(&:id),
        items: serialized_offer_items(matched_items),
        broadcast_radius: @current_radius,
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
        title: "📢 New B2B Order Request Created",
        message: "#{@actor.dealer_code} created B2B request for #{product_name} (Qty: #{total_items}). Amount: ₹#{total_amount}",
        visible_in_app: true,
        delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
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

  def formatted_phone_for(dealer)
    return nil if dealer.phone.blank?

    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
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

  def expire_order!
    @order.update!(
      status: "expired",
      request_status: "expired"
    )
  end
end
