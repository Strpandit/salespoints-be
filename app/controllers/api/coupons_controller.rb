module Api
  class CouponsController < ApplicationController
    before_action :require_dealer!
    before_action :set_coupon, only: [:show, :update, :destroy]

    def index
      coupons = current_dealer.coupons.order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      render json: serialize_resource(coupons, CouponSerializer).merge(
        meta: {
          current_page: coupons.current_page,
          next_page: coupons.next_page,
          prev_page: coupons.prev_page,
          total_pages: coupons.total_pages,
          total_count: coupons.total_count
        },
        message: "Coupons fetched successfully"
      ), status: :ok
    end

    def show
      render json: serialize_resource(@coupon, CouponSerializer).merge(message: "Coupon fetched successfully"), status: :ok
    end

    def create
      coupon = current_dealer.coupons.new(coupon_params)
      if coupon.save
        render json: serialize_resource(coupon, CouponSerializer).merge(message: "Coupon created successfully"), status: :created
      else
        render json: { error: coupon.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @coupon.update(coupon_params)
        render json: serialize_resource(@coupon, CouponSerializer).merge(message: "Coupon updated successfully"), status: :ok
      else
        render json: { error: @coupon.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @coupon.update!(is_active: false)
      render json: { message: "Coupon deactivated successfully" }, status: :ok
    end

    private

    def require_dealer!
      return if current_dealer.present?

      render json: { error: "Dealer only" }, status: :unauthorized
    end

    def set_coupon
      @coupon = current_dealer.coupons.find_by(id: params[:id])
      render json: { error: "Coupon not found" }, status: :not_found unless @coupon
    end

    def coupon_params
      params.require(:coupon).permit(
        :code, :title, :description, :audience, :discount_type, :discount_value, :max_discount,
        :min_cart_amount, :max_uses, :per_user_limit, :starts_at, :expires_at, :is_active
      )
    end
  end
end
