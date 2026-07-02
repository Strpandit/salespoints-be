class B2bWholesalerDirectOrderService
  include Rails.application.routes.url_helpers
  COD_LIMIT = 50_000.to_d

  def initialize(buyer:, seller:, wholesaler_post:, quantity:, latitude:, longitude:, requested_radius_km: nil, payment_method:, payment_status: "pending", buyer_payment_attempt: nil)
    @buyer = buyer
    @seller = seller
    @wholesaler_post = wholesaler_post
    @quantity = quantity.to_i.positive? ? quantity.to_i : 1
    @latitude = latitude.to_f
    @longitude = longitude.to_f
    @requested_radius_km = requested_radius_km || 5.0
    @payment_method = payment_method.to_s.presence || "cod"
    @payment_status = payment_status.to_s.presence || "pending"
    @buyer_payment_attempt = buyer_payment_attempt
  end

  def call
    validate!
    if @requested_radius_km <= 0
      raise "Requested radius km must be greater than 0"
    end
    
    raise StandardError, "Insufficient stock" if @wholesaler_post.stock_quantity.to_i < @quantity

    dealer_product = @wholesaler_post.dealer_product
    raise StandardError, "Dealer product mapping not found" unless dealer_product

    variant = dealer_product.product_variant
    raise StandardError, "Product variant not found" unless variant

    pricing = calculate_pricing(variant)
    check_cod_limit(pricing[:total])

    order = nil

    ActiveRecord::Base.transaction do
      order = B2bOrder.create!(
        buyer_dealer_id: @buyer.id,
        seller_dealer_id: @seller.id,
        request_status: "pending_request",
        status: "pending_request",
        requested_at: Time.current,
        requested_radius_km: @requested_radius_km,
        latitude: @latitude,
        longitude: @longitude,
        subtotal_amount: pricing[:subtotal],
        tax_amount: pricing[:gst_amount],
        discount_amount: 0,
        total_amount: pricing[:total],
        expires_at: 10.minutes.from_now,
        payment_method: @payment_method,
        payment_status: @payment_status,
        buyer_payment_attempt: @buyer_payment_attempt,
        is_direct_buy: true,
        source_type: "WholesalerPost",
        source_id: @wholesaler_post.id
      )

      item = B2bOrderItem.create!(
        b2b_order: order,
        product_variant_id: variant.id,
        quantity: @quantity,
        unit_price: pricing[:unit_price],
        total_price: pricing[:subtotal],
        dealer_product_id: dealer_product.id,
        wholesaler_post_id: @wholesaler_post.id,
        status: "open"
      )

      offer = B2bOrderOffer.create!(
        b2b_order: order,
        dealer: @seller,
        status: "open",
        delivery_channel: "whatsapp",
        item_ids: [item.id],
        delivery_payload: {
          request_id: order.id,
          wholesaler_post_id: @wholesaler_post.id,
          post_title: @wholesaler_post.title,
          product_name: item.product_variant&.product&.name,
          quantity: item.quantity,
          unit_price: item.unit_price.to_f,
          total_price: item.total_price.to_f,
          buyer_name: @buyer.dealer_code,
          buyer_phone: formatted_phone_for(@buyer)
        },
        accept_token: "b2b_accept_#{SecureRandom.hex(8)}",
        reject_token: "b2b_reject_#{SecureRandom.hex(8)}",
        recipient_phone: formatted_phone_for(@seller),
        expires_at: order.expires_at,
        rebroadcast_count: 0,
        whatsapp_status: "pending"
      )
      
      send_wholesaler_request_template(order, item, offer)
      create_wholesaler_in_app_notification(order, item, offer)
    end

    order
  rescue StandardError => e
    Rails.logger.error "B2bWholesalerDirectOrderService error: #{e.message}"
    raise
  end

  private

  def validate!
    raise StandardError, "Current location is required" if @latitude.zero? || @longitude.zero?
    raise StandardError, "Invalid payment method" unless B2bOrder::PAYMENT_METHODS.include?(@payment_method)
  end

  def calculate_pricing(variant)
    Pricing::PriceCalculator.new(
      variant: variant,
      quantity: @quantity,
      user_type: :dealer
    ).call
  end

  def check_cod_limit(total)
    if @payment_method == "cod" && total > COD_LIMIT
      raise StandardError, "COD is allowed only up to Rs 50,000"
    end
  end

  def send_wholesaler_request_template(order, item, offer)
    product = nil
    variant = nil

    if @wholesaler_post.present?
      product_name = @wholesaler_post.title || "Product"
      variant_name = @wholesaler_post.modal_no || "Standard"
      sku = @wholesaler_post.modal_no || "N/A"
      unit_price = @wholesaler_post.price || 0
      product = nil
      variant = nil
    else
      variant = item.product_variant
      product = variant&.product
      product_name = product&.name || "Product"
      variant_name = variant&.variant_sku || variant&.variant_attributes&.to_s || "Standard"
      sku = variant&.variant_sku || "N/A"
      unit_price = item.unit_price || 0
    end

    quantity = item.quantity
    total_amount = item.total_price || 0

    buyer_location = @buyer&.dealer_location
    seller_location = @seller&.dealer_location

    delivery_location = get_location(@seller)
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
    image_url = get_product_image(product, variant)

    accept_token = offer.accept_token
    reject_token = offer.reject_token

    MetaWhatsappCloudService.new.send_dealer_order_request(
      to: formatted_phone_for(@seller),
      product: product_name,
      variant: variant_name,
      sku: sku,
      price: unit_price.to_f.round(2).to_s,
      quantity: quantity.to_s,
      total_amount: total_amount.to_f.round(2).to_s,
      delivery_location: delivery_location,
      approx_distance: approx_distance,
      accept_token: accept_token,
      reject_token: reject_token,
      image_url: image_url
    )

    offer.update!(whatsapp_status: "sent", sent_at: Time.current)
  rescue StandardError => e
    Rails.logger.error("Failed to send dealer_order_request template: #{e.message}")
    Rails.logger.error e.class
    Rails.logger.error e.message
    Rails.logger.error e.backtrace.join("\n")
    offer.update!(whatsapp_status: "failed", failed_at: Time.current, failure_reason: e.message)
  end

  def create_wholesaler_in_app_notification(order, item, offer)
    variant = item.product_variant
    product = variant&.product

    if @wholesaler_post.present?
      product_name = @wholesaler_post.title || "Product"
    else
      product_name = product&.name || "Product"
    end

    quantity = item.quantity
    total_amount = item.total_price || 0

    NotificationService.deliver(
      recipient: @seller,
      actor: @buyer,
      notifiable: order,
      kind: "b2b_wholesaler_direct_buy",
      title: "📦 New Direct Buy Request",
      message: "#{@buyer.dealer_code} wants to buy #{quantity} unit(s) of #{product_name} from your post. Total: ₹#{total_amount}",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
      payload: {
        offer_id: offer.id,
        order_id: order.id,
        buyer_dealer_id: @buyer.id,
        seller_dealer_id: @seller.id,
        wholesaler_post_id: @wholesaler_post.id,
        post_title: @wholesaler_post.title,
        item_ids: [item.id],
        direct_buy: true,
        source: "wholesaler_post",
        product_name: product_name,
        quantity: quantity,
        total_amount: total_amount.to_f,
        buyer_name: @buyer.dealer_code,
        buyer_phone: formatted_phone_for(@buyer),
        payment_method: @payment_method,
        payment_status: @payment_status
      }
    )
  end

  def get_product_image(product, variant)

    if @wholesaler_post.present? && @wholesaler_post.media.attached?
      attachment = @wholesaler_post.media.first
      return rails_blob_url(attachment, only_path: false) if attachment.present?
    end

    if variant.present? && variant.media.attached?
      attachment = variant.media.first
      return rails_blob_url(attachment, only_path: false) if attachment.present?
    end

    if product.present? && product.media.attached?
      attachment = product.media.first
      return rails_blob_url(attachment, only_path: false) if attachment.present?
    end
    "#{ENV['FRONTEND_URL'] || 'https://salespoints.in'}/images/ac.png"
  rescue StandardError => e
    Rails.logger.error("Failed to get product image: #{e.message}")
    nil
  end

  def get_location(dealer)
    return "Location not available" if dealer.blank?
    
    address = dealer.dealer_profile&.business_address
    return "Location not available" if address.blank?
    
    trimmed = address.to_s.strip.truncate(60, separator: ' ')
    
    trimmed
  end

  def formatted_phone_for(dealer)
    return nil if dealer.phone.blank?
    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
  end
  
  def host_url
    @host_url ||= ENV['FRONTEND_URL'] || 'https://salespoints.in'
  end
end
