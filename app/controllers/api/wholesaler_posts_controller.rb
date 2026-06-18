module Api
  class WholesalerPostsController < ApplicationController
    before_action :require_admin!, only: [:pending, :approve, :reject]

    def index
      posts = WholesalerPost.includes(:media_attachments, dealer: :dealer_profile)
                            .order(Arel.sql("COALESCE(rating, 0) DESC"), created_at: :desc)

      if current_dealer.present?
        posts = posts.where(
          "(approve_status = :approved AND created_at >= :cutoff) OR dealer_id = :dealer_id",
          approved: "approved",
          cutoff: 7.days.ago,
          dealer_id: current_dealer.id
        )
        posts = posts.where("? = ANY(pincodes)", current_dealer.pincode)
      elsif current_admin.present?
        posts = current_admin.accessible_wholesale_posts(posts)
      else
        posts = posts.where(approve_status: "approved").visible_to_marketplace
      end

      # posts = apply_distance_filter(posts)
      posts = posts.where("title ILIKE ?", "%#{params[:search]}%") if params[:search].present?
      posts = posts.where("? = ANY(pincodes)", params[:pincode]) if params[:pincode].present?
      paginated = Kaminari.paginate_array(posts.to_a).page(params[:page]).per(params[:per_page] || 20)

      current_ratings = {}
      if current_dealer.present? && paginated.any?
        current_ratings = WholesalerPostRating
          .where(dealer_id: current_dealer.id, wholesaler_post_id: paginated.map(&:id))
          .pluck(:wholesaler_post_id, :rating)
          .to_h
      end

      render json: {
        data: paginated.map { |post| post_payload(post, current_ratings[post.id]) },
        meta: {
          current_page: paginated.current_page,
          next_page: paginated.next_page,
          prev_page: paginated.prev_page,
          total_pages: paginated.total_pages,
          total_count: paginated.total_count
        }
      }, status: :ok
    end

    def show
      post = WholesalerPost.includes(:media_attachments, dealer: :dealer_profile).find_by(id: params[:id])
      return render json: { error: "Not found" }, status: :not_found unless post

      unless post.visible_to_others? || current_dealer&.id == post.dealer_id || current_admin.present?
        return render json: { error: "Post is no longer visible" }, status: :forbidden
      end

      my_rating = current_dealer&.wholesaler_post_ratings&.find_by(wholesaler_post_id: post.id)&.rating
      render json: { data: post_payload(post, my_rating) }, status: :ok
    end

    def create
      return render json: { error: "Only dealers can create posts" }, status: :forbidden unless current_dealer

      if params[:wholesaler_post][:pincodes].blank?
        return render json: { error: "At least one pincode required" }, status: :unprocessable_entity
      end

      post = current_dealer.wholesaler_posts.new(wholesaler_post_params)
      post.approve_status = "pending"

      return render json: { error: "Invalid dealer product selection" }, status: :unprocessable_entity if invalid_dealer_product?(post.dealer_product_id)

      if post.save
        render json: { data: post_payload(post), message: "Post submitted for admin review" }, status: :created
      else
        render json: { error: post.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def pending
      scope = WholesalerPost.includes(:media_attachments, dealer: :dealer_profile).order(created_at: :desc)
      scope = scope.where(approve_status: params[:status]) if params[:status].present? && params[:status] != "all"
      paginated = scope.page(params[:page]).per(params[:per_page] || 15)

      render json: {
        data: paginated.map { |post| post_payload(post) },
        meta: {
          current_page: paginated.current_page,
          next_page: paginated.next_page,
          prev_page: paginated.prev_page,
          total_pages: paginated.total_pages,
          total_count: paginated.total_count
        }
      }
    end

    def approve
      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: "Not found" }, status: :not_found unless post

      post.update!(
        approve_status: "approved",
        reviewed_at: Time.current,
        rejection_reason: nil,
        reviewed_by_admin: current_admin
      )

      render json: { message: "Post approved", data: post_payload(post) }
    end

    def reject
      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: "Not found" }, status: :not_found unless post

      post.update!(
        approve_status: "rejected",
        rejection_reason: params[:rejection_reason],
        reviewed_at: Time.current,
        reviewed_by_admin: current_admin
      )

      render json: { message: "Post rejected", data: post_payload(post) }
    end

    def update
      return render json: { error: "Only dealers can edit posts" }, status: :forbidden unless current_dealer

      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: "Post not found" }, status: :not_found unless post
      return render json: { error: "You can edit only your own post" }, status: :forbidden unless post.dealer_id == current_dealer.id
      return render json: { error: "Invalid dealer product selection" }, status: :unprocessable_entity if invalid_dealer_product?(wholesaler_post_params[:dealer_product_id])

      if params[:wholesaler_post][:pincodes].blank?
        return render json: { error: "At least one pincode required" }, status: :unprocessable_entity
      end

      post.assign_attributes(wholesaler_post_params)
      post.approve_status = "pending" if post.changed?
      post.reviewed_at = nil if post.changed?
      post.reviewed_by_admin = nil if post.changed?
      post.rejection_reason = nil if post.changed?

      if post.save
        render json: { data: post_payload(post, current_dealer_rating_for(post)), message: "Post updated and sent for review" }, status: :ok
      else
        render json: { error: post.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      return render json: { error: "Only dealers can delete posts" }, status: :forbidden unless current_dealer

      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: "Post not found" }, status: :not_found unless post
      return render json: { error: "You can delete only your own post" }, status: :forbidden unless post.dealer_id == current_dealer.id

      post.destroy
      render json: { message: "Post deleted" }, status: :ok
    end

    def buy
      return render json: { error: "Only dealers can buy" }, status: :forbidden unless current_dealer

      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: "Post not found" }, status: :not_found unless post
      return render json: { error: "Post is no longer visible" }, status: :unprocessable_entity unless post.visible_to_others?

      if post.dealer_id == current_dealer.id
        return render json: { error: "Cannot buy your own products" }, status: :unprocessable_entity
      end

      unless post.dealer_product
        return render json: { error: "Post has no dealer product attached" }, status: :unprocessable_entity
      end

      cart = current_dealer.cart || current_dealer.create_cart
      item = cart.cart_items.find_or_initialize_by(dealer_product: post.dealer_product)
      qty = params[:quantity].to_i.positive? ? params[:quantity].to_i : 1
      item.quantity = (item.quantity || 0) + qty
      item.total_price = post.dealer_product.product_variant.inclusive_dealer_selling_price.to_f * item.quantity

      if item.save
        render json: { data: item, message: "Added to cart" }, status: :ok
      else
        render json: { error: item.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def rate
      return render json: { error: "Only dealers can rate" }, status: :forbidden unless current_dealer

      post = WholesalerPost.find_by(id: params[:id])
      return render json: { error: "Post not found" }, status: :not_found unless post
      return render json: { error: "Post is no longer visible" }, status: :unprocessable_entity unless post.visible_to_others?
      return render json: { error: "Cannot rate your own post" }, status: :unprocessable_entity if post.dealer_id == current_dealer.id

      rating_value = params[:rating].to_f
      return render json: { error: "Rating must be between 1 and 5" }, status: :unprocessable_entity unless rating_value.between?(1, 5)

      dealer_rating = post.wholesaler_post_ratings.find_or_initialize_by(dealer_id: current_dealer.id)
      dealer_rating.rating = rating_value
      dealer_rating.save!

      post.update!(
        rating: post.wholesaler_post_ratings.average(:rating).to_f.round(2),
        rating_count: post.wholesaler_post_ratings.count
      )

      render json: { data: post_payload(post, dealer_rating.rating), message: "Rating submitted" }, status: :ok
    end

    private

    def require_admin!
      return if current_user_type == "AdminUser"

      render json: { error: "Admin only" }, status: :forbidden
    end

    def wholesaler_post_params
      params.require(:wholesaler_post).permit(:title, :body, :price, :stock_quantity, :modal_no, :dealer_product_id, media: [], pincodes: [])
    end

    def invalid_dealer_product?(dealer_product_id)
      return false if dealer_product_id.blank?

      current_dealer.dealer_products.find_by(id: dealer_product_id).blank?
    end

    def current_dealer_rating_for(post)
      return nil unless current_dealer

      current_dealer.wholesaler_post_ratings.find_by(wholesaler_post_id: post.id)&.rating
    end

    # def apply_distance_filter(posts)
    #   buyer_latitude = params[:latitude].presence&.to_f
    #   buyer_longitude = params[:longitude].presence&.to_f

    #   if (buyer_latitude.blank? || buyer_longitude.blank?) && current_dealer&.dealer_location&.latitude.present? && current_dealer.dealer_location.longitude.present?
    #     buyer_latitude = current_dealer.dealer_location.latitude.to_f
    #     buyer_longitude = current_dealer.dealer_location.longitude.to_f
    #   end

    #   default_radius = current_dealer&.dealer_location&.service_radius_km.present? ? current_dealer.dealer_location.service_radius_km.to_f : 5.0
    #   requested_radius = params[:radius_km].presence&.to_f
    #   effective_radius = requested_radius&.positive? ? requested_radius : default_radius

    #   posts.select do |post|
    #     next true if current_dealer.present? && post.dealer_id == current_dealer.id
    #     next true unless buyer_latitude.present? && buyer_longitude.present?

    #     seller_location = post.dealer&.dealer_location
    #     next false unless seller_location&.latitude.present? && seller_location.longitude.present? && seller_location.is_active

    #     distance = DealerLocation.distance_km(
    #       buyer_latitude,
    #       buyer_longitude,
    #       seller_location.latitude,
    #       seller_location.longitude
    #     )

    #     post.define_singleton_method(:distance_km) { distance.round(2) }
    #     distance <= effective_radius && distance <= seller_location.service_radius_km.to_f
    #   end
    # end

    def post_payload(post, current_user_rating = nil)
      dealer = post.dealer
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
        pincodes: post.pincodes,
        approve_status: post.approve_status,
        rejection_reason: post.rejection_reason,
        reviewed_at: post.reviewed_at,
        visible_until: post.visible_until,
        is_expired: !post.visible_to_others?,
        is_owner: current_dealer.present? && post.dealer_id == current_dealer.id,
        dealer_id: post.dealer_id,
        dealer_product_id: post.dealer_product_id,
        dealer_name: dealer_display_name(dealer),
        dealer: dealer && {
          id: dealer.id,
          dealer_code: dealer.dealer_code,
          full_name: dealer.full_name,
          email: dealer.email,
          business_name: dealer.dealer_profile&.business_name,
          store_image: dealer.dealer_profile&.store_image&.attached? ? 
            dealer.dealer_profile.store_image.map { |file| attachment_payload(file) } :
            []
        },
        distance_km: post.respond_to?(:distance_km) ? post.distance_km : nil,
        media: post.media.map { |file| attachment_payload(file) },
        created_at: post.created_at
      }
    end

    def attachment_payload(file)
      {
        id: file.id,
        url: rails_blob_url(file, host: request.base_url),
        filename: file.filename.to_s,
        content_type: file.content_type.to_s
      }
    end

    def dealer_display_name(dealer)
      return "Dealer" unless dealer
      return "#{dealer.dealer_profile.business_name} (#{dealer.dealer_code})" if dealer.dealer_profile&.business_name.present?
      return "Dealer Code: #{dealer.dealer_code}" if dealer.dealer_code.present?

      "Dealer ##{dealer.id}"
    end
  end
end
