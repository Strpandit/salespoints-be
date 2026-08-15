class B2cOrderBroadcastService
  include Rails.application.routes.url_helpers

  def initialize(order:, actor:)
    @order = order
    @actor = actor
  end

  def broadcast!
    return if @order.cancelled?
    items = @order.order_items.includes(product_variant: :product).to_a
    return if items.empty?

    eligible_dealers = find_eligible_dealers(items)
    return if eligible_dealers.empty?

    ActiveRecord::Base.transaction do
      eligible_dealers.each do |dealer, matched_items|
        tracker = OrderBroadcastTracker.find_or_initialize_by(
          order: @order,
          dealer: dealer
        )

        tracker.assign_attributes(
          broadcast_radius_km: dealer.dealer_location&.service_radius_km || 5,
          attempt_count: 1,
          last_broadcast_at: Time.current,
          status: "pending"
        )
        tracker.save!

        offer = OrderOffer.find_or_initialize_by(order: @order, dealer: dealer)

        next if offer.whatsapp_status == "sent"

        if offer.new_record?
          offer.assign_attributes(
            status: "open",
            delivery_channel: "whatsapp",
            item_ids: matched_items.map(&:id),
            delivery_payload: serialized_offer_items(matched_items),
            accept_token: "accept_#{SecureRandom.hex(8)}",
            reject_token: "reject_#{SecureRandom.hex(8)}",
            recipient_phone: formatted_phone_for(dealer),
            expires_at: @order.expires_at || 4.hours.from_now,
            whatsapp_status: "pending",
            rebroadcast_count: 0
          )
          offer.save!
        end

        send_dealer_order_request(offer, dealer, matched_items)
        
        create_in_app_notification(dealer, offer, matched_items)
      end
    end

    EmailDispatcherService.retail_order_placed(@order)
  end

  private

  def find_eligible_dealers(items)
    buyer_location = get_shipping_location
    return {} if buyer_location.blank?

    variant_ids = items.map(&:product_variant_id)

    potential_dealers = Dealer.active
                              .includes(:dealer_location, dealer_products: [:product_variant])
                              .where(dealer_products: {
                                product_variant_id: variant_ids,
                                sell_in_b2c: true,
                                is_active: true,
                                approve_status: "approved"
                              })
                              .where("dealer_products.stock_quantity > 0")
                              .distinct

    return {} if potential_dealers.empty?

    matches = {}

    potential_dealers.each do |dealer|
      location = dealer.dealer_location
      next unless location&.is_active?
      next if location.latitude.blank? || location.longitude.blank?
      
      service_radius = location.service_radius_km.to_f
      next if service_radius <= 0

      distance = DealerLocation.distance_km(
        buyer_location[:latitude].to_f,
        buyer_location[:longitude].to_f,
        location.latitude.to_f,
        location.longitude.to_f
      )
        
      next if distance > service_radius

      matched_items = items.select do |item|
        dealer.dealer_products.any? do |dp|
          dp.sell_in_b2c? && 
          dp.product_variant_id == item.product_variant_id &&
          dp.stock_quantity.to_i >= item.quantity.to_i &&
          (item.product_variant_color_id.blank? || dp.color_stock_for(item.product_variant_color_id) >= item.quantity.to_i)
        end
      end

      matches[dealer] = matched_items if matched_items.any?
    end

    matches
  end

  def send_dealer_order_request(offer, dealer, matched_items)
    first_item = matched_items.first
    variant = first_item&.product_variant
    product = variant&.product
    
    product_name = product&.name || "Product"
    variant_name = variant&.variant_sku || "Standard"
    sku = product&.sku || variant&.variant_sku || "N/A"
    unit_price = first_item&.unit_price || 0
    quantity = matched_items.sum(&:quantity)
    total_amount = matched_items.sum(&:total_price)

    buyer = @order.buyer
    address = @order.shipping_address
    shipping_location = get_shipping_location

    delivery_location = if address.present?
      [
        address["address_line1"],
        address["city"],
        address["state"],
        address["postal_code"]
      ].compact.join(", ")
    else
      "Customer Location"
    end

    seller_location = dealer&.dealer_location
    approx_distance = if shipping_location.present? && seller_location.present? &&
                        seller_location.latitude.present? && seller_location.longitude.present?
      DealerLocation.distance_km(
        shipping_location[:latitude].to_f,
        shipping_location[:longitude].to_f,
        seller_location.latitude.to_f,
        seller_location.longitude.to_f
      ).round(2).to_s
    else
      "0"
    end

    image_url = get_product_image(product, variant)

    response = MetaWhatsappCloudService.new.send_dealer_order_request(
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
      order_type: "Retail",
      image_url: image_url
    )

    offer.update!(whatsapp_status: "sent", sent_at: Time.current, whatsapp_message_id: response.dig("messages",0,"id"),)
  rescue StandardError => e
    offer.update!(whatsapp_status: "failed", failed_at: Time.current, failure_reason: e.message)
  end

  def create_in_app_notification(dealer, offer, matched_items)
    total_items = matched_items.sum(&:quantity)
    total_amount = matched_items.sum(&:total_price)
    first_item = matched_items.first
    product_name = first_item&.product_variant&.product&.name || "Product"

    notification = NotificationService.deliver(
      recipient: dealer,
      actor: @actor,
      notifiable: @order,
      kind: "b2c_order_request",
      title: "📦 New Order Request",
      message: "#{@actor.full_name} wants to buy #{total_items} unit(s) of #{product_name}. Total: ₹#{total_amount}",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        offer_id: offer.id,
        order_id: @order.order_number,
        dealer_id: dealer.id,
        buyer_name: @actor.full_name,
        total_amount: total_amount.to_f,
        item_ids: matched_items.map(&:id),
        items: serialized_offer_items(matched_items)
      }
    )
    offer.update!(notification: notification)
    notification
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

    "#{ENV['FRONTEND_URL']}/images/ac.png"
  end

  def get_shipping_location
    address = @order.shipping_address
    
    if address.present?
      full_address = [
        address["address_line1"],
        address["city"],
        address["state"],
        address["postal_code"]
      ].compact.join(", ")

      if full_address.present?
        results = Geocoder.search(full_address)
        if results.any?
          return {
            latitude: results.first.latitude,
            longitude: results.first.longitude
          }
        end
      end
    end

    buyer = @order.buyer
    if buyer.respond_to?(:addresses)
      default_address = buyer.addresses.find_by(is_default: true)
      if default_address.present?
        full_address = [
          default_address.address_line1,
          default_address.city,
          default_address.state,
          default_address.postal_code
        ].compact.join(", ")

        results = Geocoder.search(full_address)
        if results.any?
          return {
            latitude: results.first.latitude,
            longitude: results.first.longitude
          }
        end
      end
    end

    nil
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
      }
    end
  end
end