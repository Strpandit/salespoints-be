module Api
  class WholesalerPostsController < ApplicationController
    # GET /api/wholesaler_posts
    def index
      posts = WholesalerPost.order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      render json: {
        data: posts.as_json,
        meta: {
          current_page: posts.current_page,
          next_page: posts.next_page,
          prev_page: posts.prev_page,
          total_pages: posts.total_pages,
          total_count: posts.total_count
        }
      }, status: :ok
    end

    # GET /api/wholesaler_posts/:id
    def show
      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: 'Not found' }, status: :not_found unless post
      render json: { data: post.as_json}, status: :ok
    end

    # POST /api/wholesaler_posts
    def create
      return render json: { error: 'Only dealers can create posts' }, status: :forbidden unless current_dealer

      post = current_dealer.wholesaler_posts.new(wholesaler_post_params)
      if post.save
        render json: { data: post, message: 'Post created' }, status: :created
      else
        render json: { error: post.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # POST /api/wholesaler_posts/:id/buy
    # Adds the referenced dealer_product to the buyer's cart for bulk purchase
    def buy
      return render json: { error: 'Only dealers can buy' }, status: :forbidden unless current_dealer

      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: 'Post not found' }, status: :not_found unless post

      if post.dealer_id == current_dealer.id
        return render json: { error: "Cannot buy your own post" }, status: :unprocessable_entity
      end

      unless post.dealer_product
        return render json: { error: 'Post has no dealer_product attached' }, status: :unprocessable_entity
      end

      # add to buyer's cart
      cart = current_dealer.cart || current_dealer.create_cart
      item = cart.cart_items.find_or_initialize_by(dealer_product: post.dealer_product)
      qty = params[:quantity].to_i > 0 ? params[:quantity].to_i : 1
      item.quantity = (item.quantity || 0) + qty
      item.total_price = post.dealer_product.product_variant.dealer_selling_price.to_f * item.quantity

      if item.save
        render json: { data: item, message: 'Added to cart' }, status: :ok
      else
        render json: { error: item.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def wholesaler_post_params
      params.require(:wholesaler_post).permit(:title, :body, :price, :stock_quantity, :modal_no, :dealer_product_id, images: [])
    end
  end
end
