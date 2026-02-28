module Api
  class CartItemsController < ApplicationController
    before_action :set_cart
    before_action :set_cart_item, only: [:update, :destroy]

    # POST /api/cart_items
    def create
      item = @cart.cart_items.find_or_initialize_by(dealer_product_id: params[:dealer_product_id])
      item.quantity = (item.quantity || 0) + params[:quantity].to_i
      item.total_price = calculate_price(item)

      if item.save
        render json: CartItemSerializer.new(item).serializable_hash, status: :created
      else
        render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PUT /api/cart_items/:id
    def update
      if params[:quantity]
        @cart_item.quantity = params[:quantity].to_i
        @cart_item.total_price = calculate_price(@cart_item)
      end

      if @cart_item.save
        render json: CartItemSerializer.new(@cart_item).serializable_hash
      else
        render json: { errors: @cart_item.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/cart_items/:id
    def destroy
      @cart_item.destroy
      head :no_content
    end

    private

    def set_cart
      @cart = if current_account
                current_account.cart || current_account.create_cart
              elsif current_dealer
                current_dealer.cart || current_dealer.create_cart
              else
                nil
              end
      render json: { error: 'Cart not found' }, status: :not_found unless @cart
    end

    def set_cart_item
      @cart_item = @cart.cart_items.find(params[:id])
    end

    def calculate_price(item)
      variant = item.dealer_product
      price_per_unit = variant.product_variant.dealer_selling_price.to_f
      price_per_unit * item.quantity
    end
  end
end