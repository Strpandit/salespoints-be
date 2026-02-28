module Api
  class DealerProductsController < ApplicationController
    skip_before_action :authenticate_request!, only: [:shop_index, :similar]
    before_action :set_dealer_product, only: [:show, :update_stock, :approve, :reject, :revert_to_pending, :destroy, :toggle_active]

    def index
      if current_dealer
        items = current_dealer.dealer_products.includes(:product, :product_variant)
      elsif current_admin
        items = DealerProduct.includes(:dealer, :product, :product_variant)
      end

      render json: { data: ActiveModelSerializers::SerializableResource.new(items, each_serializer: DealerProductSerializer), message: 'Dealer products fetched successfully' }
    end

    # Public listing for customers – only approved, active, in-stock dealer products
    def shop_index
      items = DealerProduct.live.includes(:dealer, :product, :product_variant)

      # Optional filter by category or product
      if params[:category_id].present?
        items = items.joins(:product).where(products: { category_id: params[:category_id] })
      end

      if params[:product_id].present?
        items = items.where(product_id: params[:product_id])
      end

      if params[:search].present?
        query = params[:search].strip
        items = items.joins(:product).where("products.name ILIKE ?", "%#{query}%")
      end

      # Sorting
      case params[:sort]
      when "price_asc"
        items = items.joins(:product_variant).order("product_variants.selling_price ASC")
      when "price_desc"
        items = items.joins(:product_variant).order("product_variants.selling_price DESC")
      else
        # newest / popularity fallback
        items = items.order(created_at: :desc)
      end

      items = items.page(params[:page]).per(params[:per_page] || 20)

      render json: {
        data: ActiveModelSerializers::SerializableResource.new(items, each_serializer: DealerProductSerializer),
        meta: {
          current_page: items.current_page,
          next_page: items.next_page,
          prev_page: items.prev_page,
          total_pages: items.total_pages,
          total_count: items.total_count
        },
        message: "Dealer products fetched successfully"
      }, status: :ok
    end

    def create
      return unauthorized('Dealers only') unless current_dealer

      dp = current_dealer.dealer_products.new(dealer_product_params)
      dp.approve_status = :pending
      dp.is_active = false

      if dp.save
        render json: { data: DealerProductSerializer.new(dp), message: 'Dealer product created and sent for approval' }, status: :created
      else
        render json: { error: dp.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def show
      render json: DealerProductSerializer.new(@dealer_product)
    end

    def update_stock
      return unauthorized unless authorized_dealer_product_action?

      stock = params[:stock_quantity].to_i
      return render json:{error:"Invalid stock"} if stock < 0

      if @dealer_product.update!(stock_quantity: stock)
        render json: { data: DealerProductSerializer.new(@dealer_product), message: 'Stock updated' }, status: :ok
      else
        render json: { error: @dealer_product.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def approve
      return unauthorized('Admin only') unless current_admin

      if @dealer_product.stock_quantity.nil? || @dealer_product.stock_quantity <= 0
        return render json: { error: "Stock quantity must be greater than 0 before approval" }, status: :unprocessable_entity
      end

      if @dealer_product.approve_status == "approved"
        return render json: { error: "Dealer product is already approved" }, status: :unprocessable_entity
      end

      if @dealer_product.update(approve_status: :approved, is_active: true)
        # Notify admin about product approval
        notify_admins_about_product_action(
          @dealer_product.product.name,
          @dealer_product.dealer.full_name,
          "approved"
        )
        
        render json: { data: DealerProductSerializer.new(@dealer_product), message: 'Dealer product approved' }
      else
        render json: { error: @dealer_product.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def reject
      return unauthorized('Admin only') unless current_admin

      if @dealer_product.approve_status == "rejected"
        return render json: { error: "Dealer product is already rejected" }, status: :unprocessable_entity
      end

      rejection_reason = params[:reason] || "Does not meet quality standards"

      if @dealer_product.update(approve_status: :rejected, is_active: false)
        # Notify admin about product rejection
        notify_admins_about_product_action(
          @dealer_product.product.name,
          @dealer_product.dealer.full_name,
          "rejected",
          rejection_reason
        )
        
        render json: { data: DealerProductSerializer.new(@dealer_product), message: 'Dealer product rejected' }
      else
        render json: { error: @dealer_product.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def revert_to_pending
      return unauthorized('Admin only') unless current_admin

      if @dealer_product.approve_status != "rejected"
        return render json: { error: "Only rejected products can be reverted to pending" }, status: :unprocessable_entity
      end

      if @dealer_product.update(approve_status: :pending, is_active: false)
        # Notify admin about product revert to pending
        notify_admins_about_product_action(
          @dealer_product.product.name,
          @dealer_product.dealer.full_name,
          "reverted_to_pending"
        )
        
        render json: { data: DealerProductSerializer.new(@dealer_product), message: 'Dealer product reverted to pending' }
      else
        render json: { error: @dealer_product.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      return unauthorized('Unauthorized') unless authorized_dealer_product_action?
      @dealer_product.destroy
      render json: { message: 'Dealer product removed' }, status: :ok
    end

    def toggle_active
      return unauthorized unless authorized_dealer_product_action?

      if @dealer_product.approve_status != "approved"
        return render json: {
          error: "Product must be approved before activation"
        }, status: :unprocessable_entity
      end

      @dealer_product.update!(is_active: !@dealer_product.is_active)

      render json:{
        data: DealerProductSerializer.new(@dealer_product),
        message:"Product status updated successfully"
      }
    end

    # Public similar products for customers – based on same category
    def similar
      base_scope = DealerProduct.live.includes(:product, :product_variant)

      if params[:dealer_product_id].present?
        current = DealerProduct.live.includes(:product).find_by(id: params[:dealer_product_id])
        return render json: { error: "Dealer product not found" }, status: :not_found unless current

        items = base_scope.joins(:product)
                          .where(products: { category_id: current.product.category_id })
                          .where.not(id: current.id)
                          .limit(8)
      elsif params[:product_id].present?
        items = base_scope.where(product_id: params[:product_id]).limit(8)
      else
        items = base_scope.limit(8)
      end

      render json: {
        data: ActiveModelSerializers::SerializableResource.new(items, each_serializer: DealerProductSerializer),
        message: "Similar dealer products fetched successfully"
      }, status: :ok
    end

    private

    def dealer_product_params
      params.require(:dealer_product).permit(:product_id, :product_variant_id, :stock_quantity)
    end

    def set_dealer_product
      @dealer_product = DealerProduct.find_by(id: params[:id])
      render json: { error: 'Dealer product not found' }, status: :not_found unless @dealer_product
    end

    def authorized_dealer_product_action?
      return true if current_user_type == 'AdminUser'
      return false unless current_user_type == 'Dealer'
      current_dealer.id == @dealer_product.dealer_id
    end

    def unauthorized(msg)
      render json: { error: msg }, status: :unauthorized and return
    end

    def get_admin_emails
      AdminUser.where(is_super_admin: true).pluck(:email)
    end

    def notify_admins_about_product_action(product_name, dealer_name, action, details = nil)
      admin_emails = get_admin_emails
      admin_emails.each do |email|
        AdminNotificationMailer.product_action(email, product_name, action, dealer_name, details).deliver_later
      end
    end
  end
end
