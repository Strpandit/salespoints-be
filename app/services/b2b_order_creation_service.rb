class B2bOrderCreationService
  def initialize(request_order:, payment_method:, payment_status:, buyer_payment_attempt: nil)
    @request_order = request_order
    @payment_method = payment_method.to_s
    @payment_status = payment_status.to_s
    @buyer_payment_attempt = buyer_payment_attempt
  end

  def call
    raise StandardError, "Request order not found" unless @request_order

    ActiveRecord::Base.transaction do
      request_order = B2bOrder.lock.find(@request_order.id)
      existing_order = B2bOrder.find_by(source_type: "B2bOrder", source_id: request_order.id, request_status: nil)
      return existing_order if existing_order.present?

      ensure_request_ready!(request_order)

      final_order = B2bOrder.create!(
        buyer_dealer_id: request_order.buyer_dealer_id,
        seller_dealer_id: request_order.seller_dealer_id,
        request_status: nil,
        status: "confirmed",
        requested_at: request_order.requested_at,
        requested_radius_km: request_order.requested_radius_km,
        latitude: request_order.latitude,
        longitude: request_order.longitude,
        subtotal_amount: request_order.subtotal_amount,
        tax_amount: request_order.tax_amount,
        discount_amount: request_order.discount_amount,
        total_amount: request_order.total_amount,
        accepted_at: request_order.accepted_at || Time.current,
        expires_at: nil,
        payment_method: @payment_method,
        payment_status: @payment_status,
        buyer_payment_attempt: @buyer_payment_attempt,
        is_direct_buy: request_order.is_direct_buy,
        source_type: "B2bOrder",
        source_id: request_order.id,
        payment_confirmed_at: @payment_status == "paid" ? Time.current : nil,
        confirmed_at: Time.current
      )

      request_order.b2b_order_items.accepted_items.order(:id).each do |request_item|
        _, dealer_product_id = resolve_source!(request_item)

        B2bOrderItem.create!(
          b2b_order: final_order,
          product_variant_id: request_item.product_variant_id,
          quantity: request_item.quantity,
          unit_price: request_item.unit_price,
          total_price: request_item.total_price,
          dealer_product_id: dealer_product_id,
          wholesaler_post_id: request_item.wholesaler_post_id,
          status: "accepted",
          responded_at: request_item.responded_at || Time.current
        )

      end

      final_order.recalculate_totals!

      request_order.update!(
        status: "confirmed",
        payment_status: @payment_status,
        payment_method: @payment_method,
        payment_confirmed_at: @payment_status == "paid" ? Time.current : request_order.payment_confirmed_at,
        confirmed_at: Time.current
      )

      final_order
    end
  end

  private

  def ensure_request_ready!(request_order)
    raise StandardError, "Accepted request not found" unless request_order.request_status == "accepted_request"
    raise StandardError, "Request is no longer awaiting payment" unless request_order.pending_payment?
    raise StandardError, "Payment window has expired for this request" if request_order.expires_at.present? && request_order.expires_at < Time.current
    raise StandardError, "Seller is not assigned for this request" if request_order.seller_dealer_id.blank?
  end

  def resolve_source!(request_item)
    if request_item.wholesaler_post_id.present?
      wholesaler_post = WholesalerPost.lock.find(request_item.wholesaler_post_id)
      [wholesaler_post, wholesaler_post.dealer_product_id]
    else
      dealer_product = DealerProduct.lock.find(request_item.dealer_product_id)
      [dealer_product, dealer_product.id]
    end
  end
end
