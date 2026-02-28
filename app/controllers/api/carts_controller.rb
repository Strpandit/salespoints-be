module Api
  class CartsController < ApplicationController
    # GET /api/cart
    def show
      cart = find_or_create_cart
      render json: CartSerializer.new(cart).serializable_hash
    end

    private

    def find_or_create_cart
      if current_account
        current_account.cart || current_account.create_cart
      elsif current_dealer
        current_dealer.cart || current_dealer.create_cart
      else
        raise "Unknown buyer type"
      end
    end
  end
end