class PaymentAttemptFinalizationService
  Result = Struct.new(:orders, :b2b_order, keyword_init: true)

  def initialize(payment_attempt:)
    @payment_attempt = payment_attempt
  end

  def call
    return finalize_b2b_request! if checkout_context == "b2b_request"

    orders = []

    ActiveRecord::Base.transaction do
      attempt = PaymentAttempt.lock.find(@payment_attempt.id)
      return Result.new(orders: load_orders(attempt), b2b_order: nil) if attempt.processed?
      raise StandardError, "Payment is not marked as paid" unless attempt.paid?

      items = Array(attempt.cart_snapshot["items"]).map(&:stringify_keys)
      raise StandardError, "Payment snapshot is empty" if items.empty?

      grouped_items = items.group_by { |item| item["dealer_id"] || dealer_id_for(item["dealer_product_id"]) }

      grouped_items.each_with_index do |(dealer_id, snapshot_items), index|
        subtotal = 0.to_d
        tax = 0.to_d
        pricing_rows = []

        snapshot_items.each do |snapshot_item|
          dealer_product = DealerProduct.lock.find(snapshot_item["dealer_product_id"])

          qty = snapshot_item["quantity"].to_i

          pricing = Pricing::PriceCalculator.new(
            variant: dealer_product.product_variant,
            quantity: qty,
            user_type: attempt.buyer.is_a?(Dealer) ? :dealer : :account
          ).call

          subtotal += pricing[:subtotal]
          tax += pricing[:gst_amount]

          pricing_rows << [
            dealer_product,
            snapshot_item,
            pricing
          ]
        end

        discount_remaining ||= BigDecimal(attempt.cart_snapshot["discount_amount"].to_s)
        cart_subtotal = BigDecimal(attempt.cart_snapshot["subtotal_amount"].to_s)

        share = cart_subtotal.positive? ? subtotal / cart_subtotal : 0

        discount =
          if index == grouped_items.size - 1
            discount_remaining
          else
            allocated = (BigDecimal(attempt.cart_snapshot["discount_amount"].to_s) * share).round(2)
            discount_remaining -= allocated
            allocated
          end

        total = subtotal - discount
        financials = MarketplaceOrderFinancials.build(total_amount: total)

        order = Order.create!(
          buyer: attempt.buyer,
          seller_dealer_id: dealer_id,
          status: "pending",
          subtotal_amount: subtotal,
          tax_amount: tax,
          discount_amount: discount,
          total_amount: total,
          coupon_code: attempt.coupon_code,
          payment_method: "online",
          payment_status: "paid",
          payment_gateway: attempt.payment_gateway,
          billing_address: attempt.billing_address,
          shipping_address: attempt.shipping_address,
          payment_reference: attempt.payment_reference,
          payment_confirmed_at: attempt.paid_at || Time.current,
          gateway_order_reference: attempt.gateway_order_reference,
          payment_session_id: attempt.payment_session_id,
          payment_gateway_payload: attempt.payment_gateway_payload
        )

        order.update!(financials)

        pricing_rows.each do |dealer_product, snapshot_item, pricing|
          OrderItem.create!(
            order: order,
            dealer_product_id: dealer_product.id,
            product_variant_id: snapshot_item["product_variant_id"],
            quantity: snapshot_item["quantity"],
            unit_price: pricing[:unit_price],
            total_price: pricing[:subtotal]
          )

          qty = snapshot_item["quantity"].to_i

          dealer_product.update!(
            stock_quantity: dealer_product.stock_quantity - qty
          )

            dealer_product.update!(stock_quantity: dealer_product.stock_quantity - qty)



          end

 	 end

	 end

 	 end

        end

        orders << order
      end

      consume_coupon!(attempt)
      clear_cart_items!(attempt)

      attempt.update!(
        status: "processed",
        processed_at: Time.current,
        result_payload: {
          order_ids: orders.map(&:id),
          order_numbers: orders.map(&:order_number)
        }
      )
    end

    Result.new(orders: orders, b2b_order: nil)
  end

  private

  def finalize_b2b_request!
    order = nil

    ActiveRecord::Base.transaction do
      attempt = PaymentAttempt.lock.find(@payment_attempt.id)
      existing_order = B2bOrder.find_by(buyer_payment_attempt_id: attempt.id)
      return Result.new(orders: [], b2b_order: existing_order) if attempt.processed? && existing_order.present?
      raise StandardError, "Payment is not marked as paid" unless attempt.paid?

      metadata = attempt.result_payload.fetch("request_metadata", {}).stringify_keys
      order = B2bOrderCreationService.new(
        buyer: attempt.buyer,
        cart: attempt.buyer.cart,
        latitude: metadata["latitude"],
        longitude: metadata["longitude"],
        radius_km: metadata["radius_km"],
        payment_method: "online",
        payment_status: "paid",
        buyer_payment_attempt: attempt,
        cart_snapshot: attempt.cart_snapshot
      ).call(clear_cart: false)

      clear_cart_items!(attempt)
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

  def load_orders(attempt)
    ids = Array(attempt.result_payload["order_ids"])
    Order.where(id: ids).order(:id)
  end

  def consume_coupon!(attempt)
    return if attempt.coupon_code.blank?

    coupon = Coupon.find_by(code: attempt.coupon_code)
    coupon&.consume_for!(attempt.buyer)
  end

  def clear_cart_items!(attempt)
    cart = attempt.buyer.cart
    return if cart.blank?

    Array(attempt.cart_snapshot["items"]).each do |item|
      cart_item = cart.cart_items.find_by(id: item["cart_item_id"]) ||
                  cart.cart_items.find_by(dealer_product_id: item["dealer_product_id"], product_variant_id: item["product_variant_id"])
      next if cart_item.blank?

      remaining = cart_item.quantity.to_i - item["quantity"].to_i
      remaining > 0 ? cart_item.update!(quantity: remaining) : cart_item.destroy!
    end

    cart.revalidate_coupon!(user: attempt.buyer)
  end

  def dealer_id_for(dealer_product_id)
    DealerProduct.find(dealer_product_id).dealer_id
  end

  def checkout_context
    @payment_attempt.result_payload.fetch("checkout_context", "retail_order")
  end
end
