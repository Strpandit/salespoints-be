class B2bOrderCreationService
  def initialize(request_order:, payment_method:, payment_status:, buyer_payment_attempt: nil)
    @request_order = request_order
    @payment_method = payment_method.to_s
    @payment_status = payment_status.to_s
    @buyer_payment_attempt = buyer_payment_attempt
  end

  def call
    raise StandardError, "Request order not found" unless @request_order

    final_order = nil

    ActiveRecord::Base.transaction do
      request_order = B2bOrder.lock.find(@request_order.id)

      ensure_request_ready!(request_order)

      final_order = request_order

      request_order.b2b_order_items.accepted_items.order(:id).each do |request_item|
        _, dealer_product_id = resolve_source!(request_item)

        request_item.update!(
          dealer_product_id: dealer_product_id,
          status: "accepted",
          responded_at: request_item.responded_at || Time.current
        )

        deduct_stock!(request_item) unless request_order.is_direct_buy?
      end

      final_order.recalculate_totals!

      request_order.update!(
        payment_method: @payment_method,
        buyer_payment_attempt: @buyer_payment_attempt
      )

      request_order.mark_payment_paid! if @payment_status == "paid"

      request_order.mark_order_confirmed! unless request_order.is_direct_buy?

      final_order
    end
    
    final_order
  end
  private

  def deduct_stock!(request_item)
    if request_item.wholesaler_post_id.present?
      wholesaler_post = WholesalerPost.lock.find_by(id: request_item.wholesaler_post_id)
      raise StandardError, "Wholesaler post not found" unless wholesaler_post
      if wholesaler_post.stock_quantity.to_i < request_item.quantity.to_i
        raise StandardError, "Insufficient stock for wholesaler buy #{wholesaler_post.id}"
      end
      wholesaler_post.update!(
        stock_quantity: wholesaler_post.stock_quantity.to_i - request_item.quantity.to_i
      )
    elsif request_item.dealer_product_id.present?
      dealer_product = DealerProduct.lock.find_by(id: request_item.dealer_product_id)
      raise StandardError, "Dealer product not found" unless dealer_product
      if request_item.product_variant_color_id.present?
        dealer_product.deduct_color_stock!(request_item.product_variant_color_id, request_item.quantity)
      else
        if dealer_product.stock_quantity.to_i < request_item.quantity.to_i
          raise StandardError, "Insufficient stock for dealer product #{dealer_product.id}"
        end
        dealer_product.update!(
          stock_quantity: dealer_product.stock_quantity.to_i - request_item.quantity.to_i
        )
      end
    else
      raise StandardError, "Cannot deduct stock: no source found for request item #{request_item.id}"
    end
  end

  def ensure_request_ready!(request_order)
    if request_order.is_direct_buy?
      raise StandardError, "Order is not in pending_payment state" unless request_order.status == "pending_payment" && request_order.request_status == "pending_request"
      raise StandardError, "Payment already completed" if request_order.paid? || request_order.confirmed?
      raise StandardError, "Payment window has expired" if request_order.expires_at.present? && request_order.expires_at < Time.current
    else
      unless request_order.request_status == "accepted_request"
        raise StandardError, "Accepted request not found"
      end
      raise StandardError, "Request is not awaiting payment" unless request_order.pending_payment?
      raise StandardError, "Payment window has expired for this request" if request_order.expires_at.present? && request_order.expires_at < Time.current
      raise StandardError, "Seller is not assigned for this request" if request_order.seller_dealer_id.blank?
    end
  end

  def resolve_source!(request_item)
    if request_item.wholesaler_post_id.present?
      wholesaler_post = WholesalerPost.lock.find_by(id: request_item.wholesaler_post_id)
      raise StandardError, "Wholesaler post not found" unless wholesaler_post
      raise StandardError, "Dealer product missing for wholesaler post #{wholesaler_post.id}" if wholesaler_post.dealer_product_id.blank?
      [wholesaler_post, wholesaler_post.dealer_product_id]
    else
      raise StandardError, "Dealer product missing for request item #{request_item.id}" if request_item.dealer_product_id.blank?
      dealer_product = DealerProduct.lock.find_by(id: request_item.dealer_product_id)
      raise StandardError, "Dealer product not found" unless dealer_product
      [dealer_product, dealer_product.id]
    end
  end
end
