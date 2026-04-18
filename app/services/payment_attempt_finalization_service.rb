class PaymentAttemptFinalizationService
  Result = Struct.new(:orders, keyword_init: true)

  def initialize(payment_attempt:)
    @payment_attempt = payment_attempt
  end

  def call
    orders = []

    ActiveRecord::Base.transaction do
      attempt = PaymentAttempt.lock.find(@payment_attempt.id)
      return Result.new(orders: load_orders(attempt)) if attempt.processed?
      raise StandardError, "Payment is not marked as paid" unless attempt.paid?

      items = Array(attempt.cart_snapshot["items"]).map(&:stringify_keys)
      raise StandardError, "Payment snapshot is empty" if items.empty?

      grouped_items = items.group_by { |item| item["dealer_id"] || dealer_id_for(item["dealer_product_id"]) }
      totals = build_group_totals(grouped_items, attempt)

      grouped_items.each do |dealer_id, snapshot_items|
        order = Order.create!(
          buyer: attempt.buyer,
          seller_dealer_id: dealer_id,
          status: "pending",
          subtotal_amount: totals.fetch(dealer_id)[:subtotal],
          tax_amount: totals.fetch(dealer_id)[:tax],
          discount_amount: totals.fetch(dealer_id)[:discount],
          total_amount: totals.fetch(dealer_id)[:total],
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

        snapshot_items.each do |snapshot_item|
          dealer_product = DealerProduct.lock.find(snapshot_item["dealer_product_id"])
          raise StandardError, "Product not available" unless dealer_product.sellable?

          qty = snapshot_item["quantity"].to_i
          raise StandardError, "Insufficient stock for #{dealer_product.product&.name || 'item'}" if dealer_product.stock_quantity.to_i < qty

          OrderItem.create!(
            order: order,
            dealer_product_id: dealer_product.id,
            product_variant_id: snapshot_item["product_variant_id"],
            quantity: qty,
            unit_price: BigDecimal(snapshot_item["unit_price"].to_s),
            total_price: BigDecimal(snapshot_item["total_price"].to_s)
          )

          dealer_product.update!(stock_quantity: dealer_product.stock_quantity.to_i - qty)
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

    Result.new(orders: orders)
  end

  private

  def load_orders(attempt)
    ids = Array(attempt.result_payload["order_ids"])
    Order.where(id: ids).order(:id)
  end

  def build_group_totals(grouped_items, attempt)
    discount_remaining = BigDecimal(attempt.cart_snapshot["discount_amount"].to_s)
    cart_subtotal = BigDecimal(attempt.cart_snapshot["subtotal_amount"].to_s)
    totals = {}

    grouped_items.each_with_index do |(dealer_id, items), index|
      subtotal = items.sum { |item| BigDecimal(item["total_price"].to_s) }
      tax = items.sum do |item|
        dealer_product = DealerProduct.find(item["dealer_product_id"])
        rate = dealer_product.product&.tax_rate.to_d
        BigDecimal(item["total_price"].to_s) * rate / 100
      end

      discount =
        if index == grouped_items.size - 1
          discount_remaining
        else
          share = cart_subtotal.positive? ? (subtotal / cart_subtotal) : 0
          allocated = (BigDecimal(attempt.cart_snapshot["discount_amount"].to_s) * share).round(2)
          discount_remaining -= allocated
          allocated
        end

      totals[dealer_id] = {
        subtotal: subtotal.round(2),
        tax: tax.round(2),
        discount: discount.round(2),
        total: (subtotal + tax - discount).round(2)
      }
    end

    totals
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
end
