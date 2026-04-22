module Api
  class WholesalerPostsController < ApplicationController
    # GET /api/wholesaler_posts
    def index
      posts = WholesalerPost
        .includes(:media_attachments, dealer: :dealer_profile)
        .order(Arel.sql("COALESCE(rating, 0) DESC"), created_at: :desc)
        .page(params[:page])
        .per(params[:per_page] || 20)

      current_ratings = {}
      if current_dealer.present? && posts.any?
        current_ratings = WholesalerPostRating
          .where(dealer_id: current_dealer.id, wholesaler_post_id: posts.map(&:id))
          .pluck(:wholesaler_post_id, :rating)
          .to_h
      end

      render json: {
        data: posts.map { |post| post_payload(post, current_ratings[post.id]) },
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
      post = WholesalerPost.includes(:media_attachments, dealer: :dealer_profile).find_by(id: params[:id])
      return render json: { error: 'Not found' }, status: :not_found unless post

      my_rating = current_dealer&.wholesaler_post_ratings&.find_by(wholesaler_post_id: post.id)&.rating
      render json: { data: post_payload(post, my_rating) }, status: :ok
    end

    # POST /api/wholesaler_posts
    def create
      return render json: { error: 'Only dealers can create posts' }, status: :forbidden unless current_dealer

      post = WholesalerPost.new(wholesaler_post_params)
      post.dealer_id = current_dealer.id

      if post.dealer_product_id.present?
        dealer_product = current_dealer.dealer_products.find_by(id: post.dealer_product_id)
        return render json: { error: 'Invalid dealer product selection' }, status: :unprocessable_entity unless dealer_product
      end

      if post.save
        render json: { data: post_payload(post), message: 'Post created' }, status: :created
      else
        render json: { error: post.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # GET /api/wholesaler_posts/pending
    def pending
      posts = WholesalerPost.where(approve_status: "pending")
        .includes(:media_attachments, dealer: :dealer_profile)
                .order(created_at: :desc)
                .page(params[:page])
                .per(params[:per_page] || 15)

      render json: {
        data: posts.map { |post| post_payload(post) },
        meta: {
          current_page: posts.current_page,
          total_pages: posts.total_pages
        }
      }
    end

    # PATCH /api/wholesaler_posts/:id/approve
    def approve
      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: "Not found" }, status: :not_found unless post

      post.update!(approve_status: "approved", reviewed_at: Time.current)

      render json: { message: "Post approved" }
    end

    # PATCH /api/wholesaler_posts/:id/reject
    def reject
      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: "Not found" }, status: :not_found unless post

      post.update!(
        approve_status: "rejected",
        rejection_reason: params[:rejection_reason],
        reviewed_at: Time.current
      )

      render json: { message: "Post rejected" }
    end

    # PATCH/PUT /api/wholesaler_posts/:id
    def update
      return render json: { error: 'Only dealers can edit posts' }, status: :forbidden unless current_dealer

      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: 'Post not found' }, status: :not_found unless post
      return render json: { error: 'You can edit only your own post' }, status: :forbidden unless post.dealer_id == current_dealer.id

      if post_params_without_media[:dealer_product_id].present?
        dealer_product = current_dealer.dealer_products.find_by(id: post_params_without_media[:dealer_product_id])
        return render json: { error: 'Invalid dealer product selection' }, status: :unprocessable_entity unless dealer_product
      end

      post.assign_attributes(post_params_without_media)
      attach_media_files(post)

      if post.save
        render json: { data: post_payload(post, current_dealer_rating_for(post)), message: 'Post updated' }, status: :ok
      else
        render json: { error: post.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/wholesaler_posts/:id
    def destroy
      return render json: { error: 'Only dealers can delete posts' }, status: :forbidden unless current_dealer

      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: 'Post not found' }, status: :not_found unless post
      return render json: { error: 'You can delete only your own post' }, status: :forbidden unless post.dealer_id == current_dealer.id

      post.destroy
      render json: { message: 'Post deleted' }, status: :ok
    end

    # POST /api/wholesaler_posts/:id/buy
    # Adds the referenced dealer_product to the buyer's cart for bulk purchase
    def buy
      return render json: { error: 'Only dealers can buy' }, status: :forbidden unless current_dealer

      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: 'Post not found' }, status: :not_found unless post

      if post.dealer_id == current_dealer.id
        return render json: { error: 'Cannot buy your own products' }, status: :unprocessable_entity
      end

      unless post.dealer_product
        return render json: { error: 'Post has no dealer product attached' }, status: :unprocessable_entity
      end

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

    # POST /api/wholesaler_posts/:id/rate
    def rate
      return render json: { error: 'Only dealers can rate' }, status: :forbidden unless current_dealer

      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: 'Post not found' }, status: :not_found unless post
      return render json: { error: 'Cannot rate your own post' }, status: :unprocessable_entity if post.dealer_id == current_dealer.id

      rating_value = params[:rating].to_f
      unless rating_value.between?(1, 5)
        return render json: { error: 'Rating must be between 1 and 5' }, status: :unprocessable_entity
      end

      dealer_rating = post.wholesaler_post_ratings.find_or_initialize_by(dealer_id: current_dealer.id)
      dealer_rating.rating = rating_value
      dealer_rating.save!

      new_count = post.wholesaler_post_ratings.count
      new_avg = post.wholesaler_post_ratings.average(:rating).to_f.round(2)
      post.update!(rating: new_avg, rating_count: new_count)

      render json: { data: post_payload(post, dealer_rating.rating), message: 'Rating submitted' }, status: :ok
    end

    private

    def wholesaler_post_params
      params.require(:wholesaler_post).permit(:title, :body, :price, :stock_quantity, :modal_no, :dealer_product_id, media: [])
    end

    def post_params_without_media
      wholesaler_post_params.except(:media)
    end

    def attach_media_files(post)
      return unless wholesaler_post_params[:media].present?

      wholesaler_post_params[:media].each do |file|
        post.media.attach(file)
      end
    end

    def current_dealer_rating_for(post)
      return nil unless current_dealer

      current_dealer.wholesaler_post_ratings.find_by(wholesaler_post_id: post.id)&.rating
    end

    def post_payload(post, current_user_rating = nil)
      {
        id: post.id,
        title: post.title,
        body: post.body,
        price: post.price,
        stock_quantity: post.stock_quantity,
        modal_no: post.modal_no,
        rating: post.rating.to_f,
        rating_count: post.rating_count.to_i,
        current_user_rating: current_user_rating&.to_f,
        approve_status: post.approve_status,
        is_owner: current_dealer.present? && post.dealer_id == current_dealer.id,
        dealer_id: post.dealer_id,
        dealer_product_id: post.dealer_product_id,
        dealer_name: dealer_display_name(post.dealer),
        media: post.media.map do |file|
          {
            id: file.id,
            url: rails_blob_url(file, host: request.base_url),
            filename: file.filename.to_s,
            content_type: file.content_type.to_s
          }
        end,
        created_at: post.created_at
      }
    end

    def dealer_display_name(dealer)
      return 'Dealer' unless dealer
      return "Dealer Code: #{dealer.dealer_code}" if dealer.dealer_code.present?

      "Dealer ##{dealer.id}"
    end
  end
end
