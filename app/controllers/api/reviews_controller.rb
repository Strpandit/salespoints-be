module Api
  class ReviewsController < ApplicationController
    skip_before_action :authenticate_request!, only: [:index]
    before_action :set_reviewable, only: [:index, :create]

    def index
      if @reviewable.present?
        reviews = @reviewable.reviews.order(created_at: :desc)
        paginated = reviews.page(params[:page]).per(params[:per_page] || 20)

        render json: serialize_resource(paginated, ReviewSerializer).merge(
          meta: {
            current_page: paginated.current_page,
            next_page: paginated.next_page,
            prev_page: paginated.prev_page,
            total_pages: paginated.total_pages,
            total_count: paginated.total_count
          },
          message: "Reviews fetched successfully"
        ), status: :ok
      else
        render json: { error: "Reviewable not found" }, status: :not_found
      end
    end

    def create
      # ✅ Require authentication
      return render json: { error: "Please login to review" }, status: :unauthorized unless current_account

      # ✅ Check if user already reviewed
      if existing_review?
        return render json: { 
          error: "You have already reviewed this product" 
        }, status: :unprocessable_entity
      end

      review = @reviewable.reviews.new(review_params)
      review.account = current_account
      review.verified = user_verified?(@reviewable)

      if review.save
        render json: serialize_resource(review, ReviewSerializer).merge(
          message: "Review submitted successfully"
        ), status: :created
      else
        render json: { error: review.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def set_reviewable
      if params[:product_id].present?
        @reviewable = Product.find_by(id: params[:product_id])
        if @reviewable.blank?
          render json: { error: "Product not found" }, status: :not_found and return
        end
        return
      end

      if params[:dealer_product_id].present?
        @reviewable = DealerProduct.find_by(id: params[:dealer_product_id])
        if @reviewable.blank?
          render json: { error: "Dealer product not found" }, status: :not_found and return
        end
        return
      end

      render json: { error: "Product ID or Dealer Product ID required" }, status: :bad_request
    end

    def review_params
      params.require(:review).permit(:title, :comment, :rating)
    end

    def existing_review?
      if @reviewable.is_a?(Product)
        Review.exists?(account_id: current_account.id, product_id: @reviewable.id)
      elsif @reviewable.is_a?(DealerProduct)
        Review.exists?(account_id: current_account.id, dealer_product_id: @reviewable.id)
      else
        false
      end
    end

    def user_verified?(reviewable)
      return false unless current_account

      if reviewable.is_a?(Product)
        dealer_product_ids = DealerProduct.where(product_id: reviewable.id).pluck(:id)
        
        Order.joins(:order_items)
             .where(buyer_type: "Account", buyer_id: current_account.id)
             .where(order_items: { dealer_product_id: dealer_product_ids })
             .where(status: "delivered")
             .exists?
      elsif reviewable.is_a?(DealerProduct)
        B2bOrder.joins(:b2b_order_items)
                .where(buyer_dealer_id: current_account.id)
                .where(b2b_order_items: { dealer_product_id: reviewable.id })
                .where(status: "confirmed")
                .exists?
      else
        false
      end
    end
  end
end