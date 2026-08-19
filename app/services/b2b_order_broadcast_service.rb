class B2bOrderBroadcastService
  include Rails.application.routes.url_helpers
  DEFAULT_RADIUS = 10
  MAX_RADIUS = 30
  INCREMENT_PER_MINUTE = 2

  def initialize(order:, actor:, current_radius: nil, is_b2c: false, broadcast_center: :delivery)
    @order = order
    @actor = actor
    @current_radius = current_radius || order.current_broadcast_radius || DEFAULT_RADIUS
    @is_b2c = is_b2c
    @broadcast_center = broadcast_center
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
    case @broadcast_center
    when :buyer
      location = @order.buyer_dealer&.dealer_location
      if location&.latitude.present?
        buyer_lat = location.latitude.to_f
        buyer_lng = location.longitude.to_f
      else
        address = @order.buyer_dealer&.dealer_profile&.business_address
        coords = GoogleMapsService.instance.geocode(address)
        buyer_lat = coords[:latitude].to_f
        buyer_lng = coords[:longitude].to_f
      end
    else
      buyer_lat = @order.latitude.to_f
      buyer_lng = @order.longitude.to_f
    end

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

        if item.product_variant_color_id.present?
          next if dealer_product.color_stock_for(item.product_variant_color_id) < item.quantity.to_i
        end

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
            location.latitude.to_f,
            location.longitude.to_f
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

    full_address, broadcast_location = resolve_b2b_address_and_location
    delivery_location = mask_approx_address(full_address)
    seller_location = dealer&.dealer_location
    
    approx_distance = if broadcast_location.present? && seller_location.present? &&
                        broadcast_location[:latitude].present? && broadcast_location[:longitude].present? &&
                        seller_location.latitude.present? && seller_location.longitude.present?
      DealerLocation.distance_km(
        broadcast_location[:latitude].to_f,
        broadcast_location[:longitude].to_f,
        seller_location.latitude.to_f,
        seller_location.longitude.to_f
      ).round(2).to_s
    else
      "0"
    end

    image_url = get_product_image(product, variant)

    order_type_label =
      if @order.try(:is_direct_buy?) || @order.try(:source_type) == "WholesalerPost"
        "Direct Buy"
      else
        "B2B"
      end

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
      order_type: order_type_label,
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

  def resolve_b2b_address_and_location
    if @broadcast_center == :delivery && @order.shipping_address.present?
      full_addr = format_address_hash(@order.shipping_address)
      if full_addr.present?
        coords = if @order.latitude.present? && @order.longitude.present?
                   { latitude: @order.latitude.to_f, longitude: @order.longitude.to_f }
                 else
                   resolve_coordinates_for(@order.shipping_address, full_addr)
                 end
        return [full_addr, coords.presence || { latitude: 28.6139, longitude: 77.2090 }]
      end
    end

    buyer = @order.buyer_dealer
    business_addr = buyer&.dealer_profile&.business_address.to_s.strip
    loc = buyer&.dealer_location
    coords = if loc&.latitude.present? && loc&.longitude.present?
               { latitude: loc.latitude.to_f, longitude: loc.longitude.to_f }
             elsif business_addr.present?
               GoogleMapsService.instance.geocode(business_addr) rescue nil
             end

    [business_addr.presence || "Dealer Business Location", coords.presence || { latitude: 28.6139, longitude: 77.2090 }]
  end

  def resolve_coordinates_for(address_obj, full_text)
    lat = address_obj["latitude"].presence || address_obj[:latitude] rescue nil
    lng = address_obj["longitude"].presence || address_obj[:longitude] rescue nil
    return { latitude: lat.to_f, longitude: lng.to_f } if lat.present? && lng.present?

    pincode = address_obj["postal_code"].presence || address_obj[:postal_code] rescue nil
    if pincode.present?
      coords = B2bPincodeAvailabilityService.geocode_pincode(pincode)
      return { latitude: coords[:latitude].to_f, longitude: coords[:longitude].to_f } if coords.present?
    end

    if full_text.present?
      results = Geocoder.search(full_text) rescue []
      if results.any? && results.first.latitude.present?
        return { latitude: results.first.latitude.to_f, longitude: results.first.longitude.to_f }
      end
    end

    nil
  end

  def format_address_hash(address)
    return address.to_s if address.is_a?(String)
    return "" unless address.is_a?(Hash) || address.is_a?(ActionController::Parameters)

    parts = []
    parts << address["address_line1"].presence || address[:address_line1]
    parts << address["address_line2"].presence || address[:address_line2]
    parts << address["city"].presence || address[:city]
    parts << address["state"].presence || address[:state]
    parts << address["postal_code"].presence || address[:postal_code]
    parts << address["country"].presence || address[:country]
    parts.compact.reject(&:blank?).join(", ")
  end

  def mask_approx_address(full_address)
    return "Location not available" if full_address.blank? || full_address == "Location not available"

    cleaned = full_address.to_s
                          .gsub(/\b\d{6}\b/, "")
                          .gsub(/\b(India|Bharat)\b/i, "")
                          .gsub(/,\s*,+/, ",")
                          .strip
                          .delete_prefix(",")
                          .delete_suffix(",")
                          .strip

    if cleaned.include?(",")
      parts = cleaned.split(",").map(&:strip).reject(&:blank?)
      return parts.last(3).join(", ") if parts.size >= 3
      return parts.join(", ") if parts.any?
    end

    words = cleaned.split(/\s+/).reject(&:blank?)
    return words.last(3).join(" ") if words.size >= 3
    return words.join(" ") if words.any?

    "Location not available"
  end

  def formatted_phone_for(dealer)
    return nil if dealer.phone.blank?

    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
  end

  def serialized_offer_items(items)
    Array(items).map do |item|
      color = item.respond_to?(:product_variant_color) ? item.product_variant_color : nil
      {
        id: item.id,
        product_variant_id: item.product_variant_id,
        product_variant_color_id: item.respond_to?(:product_variant_color_id) ? item.product_variant_color_id : nil,
        color_name: color&.color_name || (item.respond_to?(:ad_hoc_color) ? item.ad_hoc_color : nil),
        color_hex: color&.color_hex,
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
    @order.expire!
  end
end
