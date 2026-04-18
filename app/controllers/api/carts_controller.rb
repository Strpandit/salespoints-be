module Api
  class CartsController < ApplicationController
    # before_action :authenticate_request
    before_action :set_cart
    before_action :set_cart_item, only: [:update_item, :remove_item]

    def current_cart
      @cart.revalidate_coupon!(user: current_buyer) if @cart&.cart_items.exists?
      render json: serialized_cart.merge(message: "Cart fetched successfully"), status: :ok
    end

    def add_item
      product = DealerProduct.live.find_by(id: params[:dealer_product_id])
      return render json: { error: "Product not available" }, status: :not_found unless product

      quantity = params[:quantity].to_i > 0 ? params[:quantity].to_i : 1

      item = @cart.cart_items.find_or_initialize_by(dealer_product_id: product.id, product_variant_id: product.product_variant_id)

      item.quantity += quantity if item.persisted?
      item.quantity ||= quantity
      item.save!

      @cart.revalidate_coupon!(user: current_buyer)
      render json: serialized_cart.merge(message: "Item added to cart successfully"), status: :created
    end

    def update_item
      qty = params[:quantity].to_i
      return render json: { errors: "Quantity must be greater than 0" }, status: :unprocessable_entity if qty <= 0

      @item.update!(quantity: qty)
      @cart.revalidate_coupon!(user: current_buyer)
      render json: serialized_cart.merge(message: "Cart item updated successfully"), status: :ok
    end

    def remove_item
      @item.destroy

      if @cart.cart_items.empty?
        @cart.remove_coupon!
        return render json: serialized_cart.merge(message: "Cart item removed successfully"), status: :ok
      end

      @cart.revalidate_coupon!(user: current_buyer)
      render json: serialized_cart.merge(message: "Cart item removed successfully"), status: :ok
    end

    def apply_coupon
      code = params[:coupon_code].to_s.strip
      return render json: { error: "Coupon code is required" }, status: :unprocessable_entity if code.blank?

      @cart.apply_coupon!(coupon_code: code, user: current_buyer)
      render json: serialized_cart.merge(message: "Coupon applied successfully"), status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def remove_coupon
      @cart.remove_coupon!
      render json: serialized_cart.merge(message: "Coupon removed successfully"), status: :ok
    end

    def checkout
      billing_address = params[:billing_address].presence || checkout_address_payload
      shipping_address = params[:shipping_address].presence || checkout_address_payload

      if params[:payment_method].to_s == "online"
        result = OnlinePaymentAttemptService.new(
          cart: @cart,
          buyer: current_buyer,
          billing_address: billing_address,
          shipping_address: shipping_address
        ).call

        return render json: {
          data: {
            payment_attempt_id: result.attempt.id,
            attempt_number: result.attempt.attempt_number,
            amount: result.attempt.amount.to_f,
            status: result.attempt.status
          },
          payment: result.payment_data,
          clears_cart: false,
          message: "Payment initiated. Order will be created only after successful payment."
        }, status: :ok
      end

      result = OrderCheckoutService.new(
        cart: @cart,
        buyer: current_buyer,
        payment_method: params[:payment_method],
        billing_address: billing_address,
        shipping_address: shipping_address
      ).call

      primary_order = result.orders.first
      serialized_orders = OrderSerializer.render(result.orders)

      render json: {
        data: result.orders.one? ? serialize_data(primary_order, OrderSerializer) : serialized_orders,
        orders: serialized_orders,
        payment: result.payment_data,
        clears_cart: true,
        message: primary_order.payment_method == "online" ? "Order created. Complete payment to confirm." : "#{result.orders.size} order(s) created successfully"
      }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def set_cart
      @cart = current_buyer.cart&.tap do |cart|
        cart.cart_items.load
      end || current_buyer.create_cart

      @cart = Cart.includes(
        cart_items: [
          :product_variant,
          dealer_product: [:product, :dealer]
        ]
      ).find(@cart.id)

      render json: { error: 'Cart not found' }, status: :not_found unless @cart
    end

    def set_cart_item
      @item = @cart.cart_items.find_by(id: params[:cart_item_id])
      return render json: { errors: "Cart item not found" }, status: :not_found unless @item
    end

    def current_buyer
      current_account || current_dealer
    end

    def serialized_cart
      serialize_resource(
        @cart,
        CartSerializer,
        include: [
          :cart_items,
          :"cart_items.dealer_product",
          :"cart_items.dealer_product.product",
          :"cart_items.dealer_product.dealer",
          :"cart_items.dealer_product.product_variant",
          :"cart_items.product_variant"
        ]
      )
    end

    def checkout_address_payload
      return {} unless current_account

      address = current_account.addresses.find_by(is_default: true) || current_account.addresses.order(created_at: :desc).first
      return {} if address.blank?

      {
        name: address.name,
        phone: address.phone,
        address_line1: address.address_line1,
        address_line2: address.address_line2,
        city: address.city,
        state: address.state,
        postal_code: address.postal_code,
        country: address.country
      }
    end
  end
end
