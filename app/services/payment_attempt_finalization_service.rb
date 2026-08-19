class PaymentAttemptFinalizationService
  include Rails.application.routes.url_helpers
  Result = Struct.new(:orders, :b2b_order, keyword_init: true)

  def default_url_options
    { host: ENV.fetch("APP_URL", "https://api.salespoints.in") }
  end

  def initialize(payment_attempt:)
    @payment_attempt = payment_attempt
  end

  def call
    attempt = PaymentAttempt.find(@payment_attempt.id)

    if attempt.processed?
      return handle_processed_attempt(attempt)
    end

    raise StandardError, "Payment is not marked as paid" unless attempt.paid?

    if checkout_context == "b2b_order"
      finalize_b2b_order!(attempt)
    else
      finalize_retail_orders!(attempt)
    end
  end

  private

  def handle_processed_attempt(attempt)
    if checkout_context == "b2b_order"
      order = B2bOrder.find_by(id: metadata["request_order_id"], buyer_payment_attempt_id: attempt.id)
      return Result.new(orders: [], b2b_order: order) if order.present?
    else
      orders = load_orders(attempt)
      return Result.new(orders: orders, b2b_order: nil) if orders.present?
    end
    Result.new(orders: [], b2b_order: nil)
  end

  def finalize_b2b_order!(attempt)
    ActiveRecord::Base.transaction do
      attempt = PaymentAttempt.lock.find(@payment_attempt.id)

      if attempt.processed?
        existing_order = find_existing_b2b_order(attempt)
        return Result.new(orders: [], b2b_order: existing_order) if existing_order.present?
        return Result.new(orders: [], b2b_order: nil)
      end

      order = process_b2b_order!(attempt)
      mark_attempt_processed!(attempt, b2b_order: order)

      Result.new(orders: [], b2b_order: order)
    end
  end

  def finalize_retail_orders!(attempt)
    orders = []

    ActiveRecord::Base.transaction do
      attempt = PaymentAttempt.lock.find(@payment_attempt.id)
      if attempt.processed?
        return Result.new(orders: load_orders(attempt), b2b_order: nil)
      end

      order_ids = Array(attempt.result_payload["order_ids"])
      orders = process_retail_orders!(order_ids, attempt)

      consume_coupon!(attempt)
      mark_attempt_processed!(attempt, order_ids: orders.map(&:id), order_numbers: orders.map(&:order_number))

      Result.new(orders: orders, b2b_order: nil)
    end
  end

  def process_b2b_order!(attempt)
    metadata = attempt.result_payload.fetch("request_metadata", {}).stringify_keys
    request_order_id = metadata["request_order_id"]
    raise StandardError, "Request order id missing" if request_order_id.blank?

    request_order = B2bOrder.find_by(id: request_order_id)
    raise StandardError, "Accepted B2B request not found" if request_order.blank?

    if request_order.expires_at.present? &&
      request_order.expires_at <= Time.current

      attempt.update!(
        status: "failed",
        failure_reason: "Payment window expired",
        failed_at: Time.current
      )

      raise StandardError, "Payment window has expired."
    end

    if request_order.payment_status == "paid"
      raise StandardError, "Payment already completed."
    end

    if request_order.is_direct_buy? && request_order.source_type == "WholesalerPost"
      return process_wholesaler_direct_order!(request_order, attempt)
    end

    order = B2bOrderCreationService.new(
      request_order: request_order,
      payment_method: "online",
      payment_status: "paid",
      buyer_payment_attempt: attempt
    ).call

    send_order_accept_to_seller(order)
    send_payment_success_to_buyer(order)
    create_buyer_online_payment_notification(order)
    create_seller_online_payment_notification(order)
    notify_admin_online_payment(order)
    EmailDispatcherService.b2b_payment_done(order)
    order
  end

  def process_wholesaler_direct_order!(order, attempt)
    raise StandardError, "Payment window has expired." if order.expires_at.present? &&
                                                      order.expires_at <= Time.current
    order.update!(
      payment_method: "online",
      payment_status: "paid",
      payment_confirmed_at: Time.current,
      buyer_payment_attempt: attempt
    )

    send_order_request_to_seller(order)
    EmailDispatcherService.b2b_request_placed(order)
    
    order
  end

  def process_retail_orders!(order_ids, attempt)
    orders = []

    Order.where(id: order_ids).find_each do |order|
      order.update!(
        payment_status: "paid",
        payment_reference: attempt.payment_reference,
        payment_confirmed_at: Time.current,
      )
      
      B2cOrderBroadcastService.new(
        order: order,
        actor: order.buyer
      ).broadcast!

      EmailDispatcherService.retail_order_placed(order)

      orders << order
    end

    orders
  end

  def find_existing_b2b_order(attempt)
    metadata = attempt.result_payload.fetch("request_metadata", {}).stringify_keys
    B2bOrder.find_by(id: metadata["request_order_id"], buyer_payment_attempt_id: attempt.id)
  end

  def load_orders(attempt)
    ids = Array(attempt.result_payload["order_ids"])
    Order.where(id: ids).order(:id)
  end

  def checkout_context
    @payment_attempt.result_payload.fetch("checkout_context", "retail_order")
  end

  def mark_attempt_processed!(attempt, b2b_order: nil, order_ids: [], order_numbers: [])
    payload = attempt.result_payload.dup || {}

    if b2b_order.present?
      payload["b2b_order_id"] = b2b_order.id
      payload["b2b_order_status"] = b2b_order.status
    end

    if order_ids.any?
      payload["order_ids"] = order_ids
      payload["order_numbers"] = order_numbers
    end

    attempt.update!(
      status: "processed",
      processed_at: Time.current,
      result_payload: payload
    )
  end

  def consume_coupon!(attempt)
    return if attempt.coupon_code.blank?
    coupon = Coupon.find_by(code: attempt.coupon_code)
    coupon&.consume_for!(attempt.buyer)
  end

  def send_order_request_to_seller(order)
    return unless order.is_direct_buy? && order.source_type == "WholesalerPost"

    offer = order.b2b_order_offers.find_by(dealer: order.seller_dealer, status: "open")
    return unless offer
    
    item = order.b2b_order_items.first
    return unless item

    seller = order.seller_dealer
    buyer = order.buyer_dealer
    variant = item.product_variant
    product = variant&.product
    wholesaler_post = item.wholesaler_post

    full_buyer_address = buyer&.dealer_profile&.business_address.presence || "Dealer Business Location"
    delivery_location = mask_approx_address(full_buyer_address)
    approx_distance = calculate_distance(buyer, seller)

    base_url = ENV["FRONTEND_URL"] || "https://salespoints.in"
    accept_url = "#{base_url}/b2b/accept/#{offer.accept_token}"
    reject_url = "#{base_url}/b2b/reject/#{offer.reject_token}"
    image_url = get_product_image(product, variant, wholesaler_post)

    accept_token = offer.accept_token
    reject_token = offer.reject_token
    order_type_label =
      if order.try(:is_direct_buy?) || wholesaler_post.present? || order.try(:source_type) == "WholesalerPost"
        "Direct Buy"
      elsif order.is_a?(Order)
        "Retail"
      else
        "B2B"
      end

    MetaWhatsappCloudService.new.send_dealer_order_request(
      to: formatted_phone_for(seller),
      product: product&.name || wholesaler_post&.title || "Product",
      variant: variant&.variant_sku || wholesaler_post&.title || "Standard",
      sku: product&.sku || wholesaler_post&.modal_no || "N/A",
      price: item.unit_price.to_f.round(2).to_s,
      quantity: item.quantity.to_s,
      total_amount: item.total_price.to_f.round(2).to_s,
      delivery_location: delivery_location,
      approx_distance: approx_distance,
      accept_token: accept_token,
      reject_token: reject_token,
      order_type: order_type_label,
      image_url: image_url
    )

    offer.update!(whatsapp_status: "sent", sent_at: Time.current)
    create_seller_request_notification(order, item)
  rescue StandardError => e
    offer&.update!(whatsapp_status: "failed", failed_at: Time.current, failure_reason: e.message)
  end

  def send_order_accept_to_seller(order)
    seller = order.seller_dealer
    return if seller.blank?

    buyer = order.buyer_dealer
    latitude, longitude, location_name, address = resolve_b2b_delivery_details(order, buyer)

    offer = order.b2b_order_offers.find_by(dealer: order.seller_dealer, status: "accepted")
    shipped_token = offer&.shipped_token

    total_amount = order.b2b_order_items.sum(:total_price).to_f.round(2).to_s
    phone = buyer.phone.presence || order.shipping_address&.dig("phone")

    MetaWhatsappCloudService.new.send_order_accept(
      to: formatted_phone_for(seller),
      dealer_code: buyer.dealer_code.to_s,
      phone: formatted_phone(phone, buyer.country_code) || "N/A",
      address: address,
      order_id: order.reference_number,
      payment_mode: order.payment_method.to_s.upcase,
      total_amount: total_amount,
      latitude: latitude.to_s,
      longitude: longitude.to_s,
      location_name: location_name,
      shipped_token: shipped_token
    )
  end

  def send_payment_success_to_buyer(order)
    buyer = order.buyer_dealer
    items = order.b2b_order_items.accepted_items.to_a
    items = order.b2b_order_items.to_a if items.empty?
    first_item = items.first
    variant = first_item&.product_variant
    wholesaler_post = first_item&.wholesaler_post
    product = variant&.product || wholesaler_post&.dealer_product&.product
    phone = buyer.phone.presence || order.shipping_address&.dig("phone")

    MetaWhatsappCloudService.new.send_payment_success(
      to: formatted_phone(phone, buyer.country_code),
      product: product&.name || wholesaler_post&.title || "Product",
      variant: variant&.variant_sku || wholesaler_post&.modal_no || "Standard",
      quantity: items.sum(&:quantity).to_s,
      unit_price: first_item&.unit_price.to_f.round(2).to_s,
      total_paid: order.total_amount.to_f.round(2).to_s,
      payment_id: order.payment_method.to_s.upcase,
      order_id: order.reference_number
    )
  end

  def create_seller_request_notification(order, item)
    variant = item.product_variant
    wholesaler_post = item.wholesaler_post
    product = variant&.product || wholesaler_post&.dealer_product&.product
    product_name = product&.name || wholesaler_post&.title || "Product"
    
    NotificationService.deliver(
      recipient: order.seller_dealer,
      actor: order.buyer_dealer,
      notifiable: order,
      kind: "b2b_wholesaler_request",
      title: "📦 New Order Request",
      message: "#{order.buyer_dealer.dealer_code} wants to buy #{item.quantity} unit(s) of #{product_name}. Total: ₹#{item.total_price}",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.reference_number,
        buyer_dealer_id: order.buyer_dealer_id,
        seller_dealer_id: order.seller_dealer_id,
        total_amount: item.total_price.to_f,
        product_name: product_name,
        quantity: item.quantity
      }
    )
  end

  def create_buyer_online_payment_notification(order)
    NotificationService.deliver(
      recipient: order.buyer_dealer,
      actor: order.buyer_dealer,
      notifiable: order,
      kind: "b2b_order_payment_success",
      title: "Payment Successful!",
      message: "Your order ##{order.reference_number} has been confirmed with Online Payment.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.reference_number,
        total_amount: order.total_amount.to_f,
        payment_method: "Online"
      }
    )
  end

  def create_seller_online_payment_notification(order)
    NotificationService.deliver(
      recipient: order.seller_dealer,
      actor: order.buyer_dealer,
      notifiable: order,
      kind: "b2b_order_payment_confirmed_seller",
      title: "Payment Confirmed!",
      message: "Buyer #{order.buyer_dealer.dealer_code} has completed payment for order ##{order.reference_number}.",
      visible_in_app: true,
      delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
      payload: {
        order_id: order.reference_number,
        buyer_dealer_id: order.buyer_dealer_id,
        total_amount: order.total_amount.to_f,
        payment_method: "Online"
      }
    )
  end

  def notify_admin_online_payment(order)
    AdminUser.where(is_super_admin: true).find_each do |admin|
      NotificationService.deliver(
        recipient: admin,
        actor: order.buyer_dealer,
        notifiable: order,
        kind: "admin_b2b_order_confirmed",
        title: "New B2B Order Confirmed (Online)",
        message: "B2B Order ##{order.reference_number} confirmed by #{order.buyer_dealer.dealer_code}. Amount: Rs #{order.total_amount} (Online Payment)",
        visible_in_app: true,
        delivery_channels: { push: true, whatsapp: false, sms: false, email: true, in_app: true },
        payload: {
          order_id: order.reference_number,
          buyer_dealer_id: order.buyer_dealer_id,
          seller_dealer_id: order.seller_dealer_id,
          total_amount: order.total_amount.to_f,
          payment_method: "Online"
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
        results = Geocoder.search(address) rescue []
        if results.any?
          name = "Salespoints Dealer Point #{dealer&.dealer_code.presence || 'N/A'}"
          return [results.first.latitude, results.first.longitude, name, address]
        end
      end
      [28.6139, 77.2090, "Default Location", address]
    end
  end

  def resolve_b2b_delivery_details(order, buyer)
    location_name = "Salespoints Dealer Point #{buyer&.dealer_code.presence || 'N/A'}"
    
    if order.shipping_address.present?
      full_addr = format_address(order.shipping_address)
      if full_addr.present? && full_addr != "Address not available"
        coords = if order.latitude.present? && order.longitude.present?
                   { latitude: order.latitude.to_f, longitude: order.longitude.to_f }
                 else
                   resolve_coordinates_for(order.shipping_address, full_addr)
                 end
        lat = coords&.dig(:latitude) || 28.6139
        lng = coords&.dig(:longitude) || 77.2090
        return [lat.to_f, lng.to_f, location_name, full_addr]
      end
    end

    business_addr = buyer&.dealer_profile&.business_address.presence || "Address not available"
    loc = buyer&.dealer_location
    if loc&.latitude.present? && loc&.longitude.present?
      [loc.latitude.to_f, loc.longitude.to_f, location_name, business_addr]
    else
      coords = (business_addr != "Address not available") ? (GoogleMapsService.instance.geocode(business_addr) rescue nil) : nil
      lat = coords&.dig(:latitude) || 28.6139
      lng = coords&.dig(:longitude) || 77.2090
      [lat.to_f, lng.to_f, location_name, business_addr]
    end
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

  def format_address(address)
    return "Address not available" if address.blank?
    
    if address.is_a?(Hash) || address.is_a?(ActionController::Parameters)
      parts = []
      parts << address["address_line1"].presence || address[:address_line1]
      parts << address["address_line2"].presence || address[:address_line2]
      parts << address["city"].presence || address[:city]
      parts << address["state"].presence || address[:state]
      parts << address["postal_code"].presence || address[:postal_code]
      parts << address["country"].presence || address[:country]
      return parts.compact.reject(&:blank?).join(", ") if parts.any?
    end
    
    address.to_s
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

  def get_location(dealer)
    return "Location not available" if dealer.blank?
    address = dealer.dealer_profile&.business_address
    return "Location not available" if address.blank?
    mask_approx_address(address)
  end

  def get_product_image(product, variant, wholesaler_post = nil)
    if wholesaler_post.present? && wholesaler_post.media.attached?
      attachment = wholesaler_post.media.first
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
    "#{ENV['FRONTEND_URL']}/images/ac.png"
  end

  def calculate_distance(buyer, seller)
    buyer_location = buyer&.dealer_location
    seller_location = seller&.dealer_location

    if buyer_location.present? && seller_location.present? &&
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
  end

  def formatted_phone_for(dealer)
    return nil if dealer.phone.blank?

    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
  end

  def formatted_phone(phone, country_code = "+91")
    return nil if phone.blank?
    "#{country_code.presence || '+91'}#{phone}".gsub(/\s+/, "")
  end
end
