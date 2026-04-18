module Api
  class ReviewsController < ApplicationController
    before_action :set_product
    before_action :authenticate_request!, only: [:create]

    def index
      reviews = @product.reviews.order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      if reviews.exists?
        render json: serialize_resource(reviews, ReviewSerializer).merge(
            meta: {
              current_page: reviews.current_page,
              next_page: reviews.next_page,
              prev_page: reviews.prev_page,
              total_pages: reviews.total_pages,
              total_count: reviews.total_count
            },
          ), status: :ok
      else
        render json: { error: "No reviews found"}, status: :not_found
      end
    end

    def create
      review = @product.reviews.new(review_params)
      review.account = current_user
      review.verified = user_verified?

      if review.save
        render json: serialize_resource(review, ReviewSerializer).merge(message: "Review created successfully"), status: :created
      else
        render json: { error: review.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def set_product
      @product = DealerProduct.find_by(id: params[:dealer_product_id])
    end

    def review_params
      params.require(:review).permit(:title, :comment, :rating, :account_id, :dealer_product_id)
    end

    def user_verified?
      current_user.status?
    end
  end
end
