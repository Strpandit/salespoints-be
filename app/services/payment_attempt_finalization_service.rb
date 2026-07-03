class PaymentAttemptFinalizationService
  Result = Struct.new(:orders, :b2b_order, keyword_init: true)

  def initialize(payment_attempt:)
    @payment_attempt = payment_attempt
  end

  def call
    attempt = PaymentAttempt.find(@payment_attempt.id)

    if attempt.processed?
      Rails.logger.info "Payment Attempt #{attempt.id} already processed. Returning existing result."

      if checkout_context == "b2b_order"
        order = B2bOrder.find_by(buyer_payment_attempt_id: attempt.id, request_status: nil)
        return Result.new(orders: [], b2b_order: order) if order.present?
      else
        orders = load_orders(attempt)
        return Result.new(orders: orders, b2b_order: nil) if orders.present?
      end

      return Result.new(orders: [], b2b_order: nil)
    end

    return finalize_b2b_request! if checkout_context == "b2b_order"

    orders = []

    ActiveRecord::Base.transaction do
      attempt = PaymentAttempt.lock.find(@payment_attempt.id)
      return Result.new(orders: load_orders(attempt), b2b_order: nil) if attempt.processed?
      raise StandardError, "Payment is not marked as paid" unless attempt.paid?

      order_ids = Array(attempt.result_payload["order_ids"])

      Order.where(id: order_ids).find_each do |order|
        order.update!(
          payment_status: "paid",
          status: "processing",
          payment_reference: attempt.payment_reference,
          payment_confirmed_at: Time.current,
          paid_at: Time.current
        )

        OrderNotificationJob.perform_later(order.id, "placed", attempt.buyer_type, attempt.buyer_id)
        OrderNotificationJob.perform_later(order.id, "payment_paid", attempt.buyer_type, attempt.buyer_id)

        orders << order
      end

      consume_coupon!(attempt)

      attempt.update!(
        status: "processed",
        processed_at: Time.current,
        result_payload: attempt.result_payload.merge(
          order_ids: orders.map(&:id),
          order_numbers: orders.map(&:order_number)
        )
      )
    end

    Result.new(orders: orders, b2b_order: nil)
  end

  private

  def finalize_b2b_request!
    order = nil

    ActiveRecord::Base.transaction do
      attempt = PaymentAttempt.lock.find(@payment_attempt.id)

      if attempt.processed?
        existing_order = B2bOrder.find_by(buyer_payment_attempt_id: attempt.id, request_status: nil)
        return Result.new(orders: [], b2b_order: existing_order) if existing_order.present?

        return Result.new(orders: [], b2b_order: nil)
      end

      raise StandardError, "Payment is not marked as paid" unless attempt.paid?

      metadata = attempt.result_payload.fetch("request_metadata", {}).stringify_keys
      existing_order = B2bOrder.find_by(buyer_payment_attempt_id: attempt.id, request_status: nil)

      if existing_order.present?
        attempt.update!(status: "processed", processed_at: Time.current)
        return Result.new(orders: [], b2b_order: existing_order)
      end

      request_order = B2bOrder.find_by(id: metadata["request_order_id"])
      raise StandardError, "Accepted B2B request not found for payment finalization" if request_order.blank?

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

      attempt.update!(
        status: "processed",
        processed_at: Time.current,
        result_payload: attempt.result_payload.merge(
          "b2b_order_id" => order.id,
          "b2b_order_status" => order.status
        )
      )
    end

    Result.new(orders: [], b2b_order: order)
  end

  def send_order_accept_to_seller(order)
    seller = order.seller_dealer
    return if seller.blank?

    buyer = order.buyer_dealer
    latitude, longitude, location_name = get_buyer_location(buyer)

    MetaWhatsappCloudService.new.send_order_accept(
      to: formatted_phone_for(seller),
      dealer_code: buyer.dealer_code.to_s,
      phone: formatted_phone_for(buyer) || "N/A",
      address: get_address(buyer),
      order_id: order.reference_number,
      latitude: latitude,
      longitude: longitude,
      location_name: location_name
    )
  rescue StandardError => e
    Rails.logger.error("Failed to send order_accept template to seller: #{e.message}")
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
      delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
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
      delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
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
        delivery_channels: { push: true, whatsapp: false, sms: false, email: false, in_app: true },
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
    return [28.6139, 77.2090, "Default Location"] if dealer.blank?

    location = dealer.dealer_location

    if location.present? && location.latitude.present? && location.longitude.present?
      name = dealer.dealer_profile&.business_name.presence || "Dealer Location"
      [location.latitude.to_f, location.longitude.to_f, name]
    else
      address = get_address(dealer)
      if address.present? && address != "Address not available"
        results = Geocoder.search(address)
        if results.any?
          name = dealer.dealer_profile&.business_name.presence || "Dealer Location"
          return [results.first.latitude, results.first.longitude, name]
        end
      end
      [28.6139, 77.2090, "Default Location"]
    end
  end

  def get_address(dealer)
    return "Address not available" if dealer.blank?

    profile = dealer.dealer_profile
    return "Address not available" if profile.blank?

    profile.business_address.presence || "Address not available"
  end

  def formatted_phone_for(dealer)
    return nil if dealer.phone.blank?

    cc = dealer.country_code.presence || "+91"
    "#{cc}#{dealer.phone}".gsub(/\s+/, "")
  end

  def load_orders(attempt)
    ids = Array(attempt.result_payload["order_ids"])
    Order.where(id: ids).order(:id)
  end

  def consume_coupon!(attempt)
    return if attempt.coupon_code.blank?

    coupon = Coupon.find_by(code: attempt.coupon_code)
    coupon&.consume_for!(attempt.buyer)
  end

  def checkout_context
    @payment_attempt.result_payload.fetch("checkout_context", "retail_order")
  end
end
