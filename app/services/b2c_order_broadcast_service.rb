class B2cOrderBroadcastService
  include Rails.application.routes.url_helpers

  def initialize(order:, actor:)
    @order = order
    @actor = actor
  end

  def broadcast!
    items = @order.order_items.includes(product_variant: :product).to_a
    return if items.empty?

    eligible_dealers = find_eligible_dealers(items)
    return if eligible_dealers.empty?

    ActiveRecord::Base.transaction do
      eligible_dealers.each do |dealer, matched_items|
        OrderBroadcastTracker.create!(
          order: @order,
          dealer: dealer,
          broadcast_radius_km: dealer.dealer_location&.service_radius_km || 5,
          attempt_count: 1,
          last_broadcast_at: Time.current,
          status: "pending"
        )

        offer = OrderOffer.find_or_initialize_by(order: @order, dealer: dealer)

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
  end

  private

  def find_eligible_dealers(items)
    pincode = @order.shipping_address["postal_code"] || @order.billing_address["postal_code"]
    return {} if pincode.blank?

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
                              .where(pincode: pincode)
                              .distinct

    matches = {}

    potential_dealers.each do |dealer|
      location = dealer.dealer_location
      next unless location&.is_active?
      
      service_radius = location.service_radius_km.to_f
      
      if service_radius > 0
        buyer_location = get_buyer_location
        next if buyer_location.blank?
        
        distance = DealerLocation.distance_km(
          buyer_location[:latitude].to_f,
          buyer_location[:longitude].to_f,
          location.latitude.to_f,
          location.longitude.to_f
        )
        
        next if distance > service_radius
      end

      matched_items = items.select do |item|
        dealer.dealer_products.any? do |dp|
          dp.sellable_in_b2c? && 
          dp.stock_quantity.to_i >= item.quantity.to_i && 
          dp.product_variant_id == item.product_variant_id
        end
      end

      matches[dealer] = matched_items if matched_items.any?
    end

    matches
  end

  def get_buyer_location
    address = @order.shipping_address
    
    if address.present?
      full_address = [
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
    latitude, longitude, location_name = get_location_from_address(address, buyer)

    image_url = get_product_image(product, variant)

    MetaWhatsappCloudService.new.send_dealer_order_request(
      to: formatted_phone_for(dealer),
      product: product_name,
      variant: variant_name,
      sku: sku,
      price: unit_price.to_f.round(2).to_s,
      quantity: quantity.to_s,
      total_amount: total_amount.to_f.round(2).to_s,
      delivery_location: location_name,
      approx_distance: "0",
      accept_token: offer.accept_token,
      reject_token: offer.reject_token,
      image_url: image_url
    )

    offer.update!(whatsapp_status: "sent", sent_at: Time.current)
  rescue StandardError => e
    offer.update!(whatsapp_status: "failed", failed_at: Time.current, failure_reason: e.message)
  end

  def create_in_app_notification(dealer, offer, matched_items)
    total_items = matched_items.sum(&:quantity)
    total_amount = matched_items.sum(&:total_price)
    first_item = matched_items.first
    product_name = first_item&.product_variant&.product&.name || "Product"

    NotificationService.deliver(
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

  def get_location_from_address(address, buyer)
    if address.present?
      full_address = [
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
        full_address = [
          default_address.city,
          default_address.state,
          default_address.postal_code
        ].compact.join(", ")

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

    ["28.6139", "77.2090", "Customer Location"]
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
end