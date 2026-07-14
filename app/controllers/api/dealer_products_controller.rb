module Api
  class DealerProductsController < ApplicationController
    skip_before_action :authenticate_request!, only: [:shop_index, :similar]
    before_action :set_dealer_product, only: [:show, :update, :update_stock, :approve, :reject, :revert_to_pending, :destroy, :toggle_active]

    def index
      if current_dealer
        items = current_dealer.dealer_products.includes(:product, :product_variant).order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      elsif current_admin
        items = DealerProduct.includes(:dealer, :product, :product_variant).order(created_at: :desc)
        if params[:approve_status].blank? || params[:approve_status] == "all"
          items = items
        else
          items = items.joins(:dealer).where(dealers: { deleted_at: nil }).where(approve_status: params[:approve_status])
        end
        items = items.page(params[:page]).per(params[:per_page] || 20)
      else
        return unauthorized("Unauthorized")
      end

      render json: serialize_resource(items, DealerProductSerializer, base_url: request.base_url).merge(
        meta: {
          current_page: items.current_page,
          next_page: items.next_page,
          prev_page: items.prev_page,
          total_pages: items.total_pages,
          total_count: items.total_count
        },
        message: "Dealer products fetched successfully"
      )
    end

    # Public listing for customers: only approved, active, in-stock dealer products.
    def shop_index
      items = DealerProduct.live.for_b2c.where("dealer_products.stock_quantity > 0").includes(:dealer, :product, :product_variant)

      if params[:category_id].present?
        items = items.joins(:product).where(products: { category_id: params[:category_id] })
      end

      if params[:product_id].present?
        items = items.where(product_id: params[:product_id])
      end

      if params[:product_variant_id].present?
        items = items.where(product_variant_id: params[:product_variant_id])
      end

      if params[:search].present?
        query = params[:search].strip
        items = items.joins(:product).where("products.name ILIKE ?", "%#{query}%")
      end

      case params[:sort]
      when "price_asc"
        items = items.joins(:product_variant).order("product_variants.selling_price ASC")
      when "price_desc"
        items = items.joins(:product_variant).order("product_variants.selling_price DESC")
      else
        items = items.order(created_at: :desc)
      end

      items = items.page(params[:page]).per(params[:per_page] || 20)

      render json: serialize_resource(items, DealerProductSerializer, base_url: request.base_url).merge(
        meta: {
          current_page: items.current_page,
          next_page: items.next_page,
          prev_page: items.prev_page,
          total_pages: items.total_pages,
          total_count: items.total_count
        },
        message: "Dealer products fetched successfully"
      ), status: :ok
    end

    # Dealer-only B2B listing: same catalog style but excludes own products.
    def b2b_shop_index
      return unauthorized("Dealers only") unless current_dealer
      buyer_latitude = params[:latitude].presence&.to_f
      buyer_longitude = params[:longitude].presence&.to_f
      if buyer_latitude.blank? || buyer_longitude.blank?
        return render json: { error: "Current location is required to browse nearby B2B products" }, status: :unprocessable_entity
      end

      configured_radius = current_dealer.dealer_location&.service_radius_km.to_f
      radius = params[:radius_km].to_f
      radius = configured_radius if radius <= 0 && configured_radius.positive?
      radius = 5.0 if radius <= 0

      items = DealerProduct.live
                           .for_b2b
                           .where("dealer_products.stock_quantity > 0")
                           .where.not(dealer_id: current_dealer.id)
                           .includes(dealer: :dealer_location, product: {}, product_variant: {})

      if params[:category_id].present?
        items = items.joins(:product).where(products: { category_id: params[:category_id] })
      end

      if params[:product_id].present?
        items = items.where(product_id: params[:product_id])
      end

      if params[:product_variant_id].present?
        items = items.where(product_variant_id: params[:product_variant_id])
      end

      if params[:search].present?
        query = params[:search].strip
        items = items.joins(:product).where("products.name ILIKE ?", "%#{query}%")
      end

      case params[:sort]
      when "price_asc"
        items = items.joins(:product_variant).order("product_variants.dealer_selling_price ASC")
      when "price_desc"
        items = items.joins(:product_variant).order("product_variants.dealer_selling_price DESC")
      else
        items = items.order(created_at: :desc)
      end

      rows = items.to_a.select do |row|
        seller_location = row.dealer&.dealer_location
        next false unless seller_location&.is_active && seller_location.latitude.present? && seller_location.longitude.present?

        distance = DealerLocation.distance_km(
          buyer_latitude,
          buyer_longitude,
          seller_location.latitude,
          seller_location.longitude
        )

        row.define_singleton_method(:distance_km) { distance.round(2) }

        distance <= radius && distance <= seller_location.service_radius_km.to_f
      end

      # One listing per product variant: nearest seller within radius (Ola/Uber-style catalog).
      best_by_variant = {}
      rows.each do |row|
        vid = row.product_variant_id
        d = row.distance_km
        prev = best_by_variant[vid]
        best_by_variant[vid] = [row, d] if prev.nil? || d < prev[1]
      end

      picked = best_by_variant.values.map do |row, d|
        row.define_singleton_method(:distance_km) { d }
        row
      end

      case params[:sort]
      when "price_asc"
        picked.sort_by! { |r| r.product_variant.dealer_selling_price.to_f }
      when "price_desc"
        picked.sort_by! { |r| -r.product_variant.dealer_selling_price.to_f }
      else
        picked.sort_by! { |r| r.distance_km }
      end

      items = Kaminari.paginate_array(picked).page(params[:page]).per(params[:per_page] || 20)
      render json: serialize_resource(items, DealerProductSerializer, base_url: request.base_url).merge(
        meta: {
          current_page: items.current_page,
          next_page: items.next_page,
          prev_page: items.prev_page,
          total_pages: items.total_pages,
          total_count: items.total_count
        },
        message: "B2B dealer products fetched successfully"
      ), status: :ok
    end

    def create
      dealer = submission_dealer
      return unauthorized("Unauthorized") unless dealer

      dealer_product = create_dealer_product_submission!(dealer)

      render json: serialize_resource(dealer_product, DealerProductSerializer, base_url: request.base_url).merge(
        message: dealer_product_creation_message
      ), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def show
      render json: serialize_resource(@dealer_product, DealerProductSerializer, base_url: request.base_url)
    end

    def update
      return unauthorized("Unauthorized") unless authorized_dealer_product_action?

      if @dealer_product.update(update_dealer_product_params)
        render json: serialize_resource(@dealer_product, DealerProductSerializer, base_url: request.base_url).merge(
          message: "Dealer product updated successfully"
        ), status: :ok
      else
        render json: { error: @dealer_product.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # Dealer-only B2B product detail.
    def b2b_show
      return unauthorized("Dealers only") unless current_dealer

      item = DealerProduct.live
                          .for_b2b
                          .where("dealer_products.stock_quantity > 0")
                          .where.not(dealer_id: current_dealer.id)
                          .includes(:dealer, :product, :product_variant)
                          .find_by(id: params[:id])
      return render json: { error: "Dealer product not found" }, status: :not_found unless item

      render json: serialize_resource(item, DealerProductSerializer, base_url: request.base_url).merge(
        message: "B2B dealer product fetched successfully"
      ), status: :ok
    end

    def update_stock
      return unauthorized("Unauthorized") unless authorized_dealer_product_action?

      stock = params[:stock_quantity].to_i
      return render json: { error: "Invalid stock" }, status: :unprocessable_entity if stock < 0

      if @dealer_product.update(stock_quantity: stock)
        render json: serialize_resource(@dealer_product, DealerProductSerializer, base_url: request.base_url).merge(message: "Stock updated"), status: :ok
      else
        render json: { error: @dealer_product.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def approve
      return unauthorized("Admin only") unless current_admin

      if @dealer_product.stock_quantity.nil? || @dealer_product.stock_quantity <= 0
        return render json: { error: "Stock quantity must be greater than 0 before approval" }, status: :unprocessable_entity
      end

      if @dealer_product.approve_status == "approved"
        return render json: { error: "Dealer product is already approved" }, status: :unprocessable_entity
      end

      if @dealer_product.update(approve_status: :approved, is_active: true)
        @dealer_product.product.update!(is_active: true) unless @dealer_product.product.is_active?
        @dealer_product.product_variant&.update!(is_active: true) unless @dealer_product.product_variant&.is_active?
        notify_admins_about_product_action(@dealer_product.product.name, @dealer_product.dealer.full_name, "approved")
        render json: serialize_resource(@dealer_product, DealerProductSerializer, base_url: request.base_url).merge(message: "Dealer product approved")
      else
        render json: { error: @dealer_product.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def reject
      return unauthorized("Admin only") unless current_admin

      if @dealer_product.approve_status == "rejected"
        return render json: { error: "Dealer product is already rejected" }, status: :unprocessable_entity
      end

      rejection_reason = params[:reason] || "Does not meet quality standards"

      if @dealer_product.update(approve_status: :rejected, is_active: false)
        notify_admins_about_product_action(@dealer_product.product.name, @dealer_product.dealer.full_name, "rejected", rejection_reason)
        render json: serialize_resource(@dealer_product, DealerProductSerializer, base_url: request.base_url).merge(message: "Dealer product rejected")
      else
        render json: { error: @dealer_product.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def revert_to_pending
      return unauthorized("Admin only") unless current_admin

      if @dealer_product.approve_status != "rejected"
        return render json: { error: "Only rejected products can be reverted to pending" }, status: :unprocessable_entity
      end

      if @dealer_product.update(approve_status: :pending, is_active: false)
        notify_admins_about_product_action(@dealer_product.product.name, @dealer_product.dealer.full_name, "reverted_to_pending")
        render json: serialize_resource(@dealer_product, DealerProductSerializer, base_url: request.base_url).merge(message: "Dealer product reverted to pending")
      else
        render json: { error: @dealer_product.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      return unauthorized("Unauthorized") unless authorized_dealer_product_action?

      @dealer_product.destroy
      render json: { message: "Dealer product removed" }, status: :ok
    end

    def toggle_active
      return unauthorized("Unauthorized") unless authorized_dealer_product_action?

      if @dealer_product.dealer.deleted_at.present?
        return render json: { 
          error: "Cannot activate product. Associated dealer is deleted." 
        }, status: :unprocessable_entity
      end

      if @dealer_product.approve_status != "approved"
        return render json: { error: "Product must be approved before activation" }, status: :unprocessable_entity
      end

      @dealer_product.update!(is_active: !@dealer_product.is_active)

      render json: serialize_resource(@dealer_product, DealerProductSerializer, base_url: request.base_url).merge(
        message: "Product status updated successfully"
      )
    end

    # Public similar products for customers.
    def similar
      base_scope = DealerProduct.live.for_b2c.where("dealer_products.stock_quantity > 0").includes(:product, :product_variant)

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

      render json: serialize_resource(items, DealerProductSerializer, base_url: request.base_url).merge(
        message: "Similar dealer products fetched successfully"
      ), status: :ok
    end

    # Dealer-only similar products for B2B details page, excluding own products.
    def b2b_similar
      return unauthorized("Dealers only") unless current_dealer

      base_scope = DealerProduct.live
                                .for_b2b
                                .where("dealer_products.stock_quantity > 0")
                                .where.not(dealer_id: current_dealer.id)
                                .includes(:product, :product_variant)

      if params[:dealer_product_id].present?
        current = base_scope.find_by(id: params[:dealer_product_id])
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

      render json: serialize_resource(items, DealerProductSerializer, base_url: request.base_url).merge(
        message: "Similar B2B dealer products fetched successfully"
      ), status: :ok
    end

    def check_pincode
      pincode = params[:pincode]
      product_variant_id = params[:product_variant_id]

      if pincode.blank?
        return render json: { error: "Pincode is required" }, status: :unprocessable_entity
      end

      if product_variant_id.blank?
        return render json: { error: "Product variant ID is required" }, status: :unprocessable_entity
      end

      eligible_dealers = Dealer.active
                              .includes(:dealer_products)
                              .where(dealer_products: {
                                product_variant_id: product_variant_id,
                                sell_in_b2c: true,
                                is_active: true,
                                approve_status: "approved"
                              })
                              .where("dealer_products.stock_quantity > 0")
                              .where(pincode: pincode)
                              .distinct

      render json: {
        deliverable: eligible_dealers.any?,
        message: eligible_dealers.any? ? "Product is available in your pincode" : "No sellers available for delivery in your pincode",
        sellers_count: eligible_dealers.count,
        sellers: eligible_dealers.map do |dealer|
          {
            id: dealer.id,
            dealer_code: dealer.dealer_code,
            business_name: dealer.dealer_profile&.business_name,
            stock_quantity: dealer.dealer_products.find_by(product_variant_id: product_variant_id)&.stock_quantity || 0
          }
        end
      }, status: :ok
    end

    private

    def dealer_product_params
      params.require(:dealer_product).permit(
        :dealer_id,
        :product_id,
        :product_variant_id,
        :stock_quantity,
        :sell_in_b2b,
        :sell_in_b2c,
        product_attributes: [
          :name, :slug, :sku, :desc, :material, :brand_id, :category_id,
          :is_featured, :is_new, :tax_rate, :price, :selling_price, :dealer_price,
          :dealer_selling_price, :discount_percentage, :variant_sku,
          media: [],
          features: [], care_instructions: [],
          product_specifications_attributes: [:id, :key, :value, :_destroy],
          product_variants_attributes: [
            :id, :variant_sku, :price, :selling_price, :dealer_price,
            :dealer_selling_price, :discount_percentage, :is_active, :_destroy,
            { media: [], variant_attributes: [:key, :value] }
          ]
        ]
      )
    end

    def submission_dealer
      return current_dealer if current_dealer
      return Dealer.find_by(id: dealer_product_params[:dealer_id]) if current_admin && dealer_product_params[:dealer_id].present?

      nil
    end

    def create_dealer_product_submission!(dealer)
      ActiveRecord::Base.transaction do
        product, variant = resolved_product_and_variant_for_submission
        status = submission_status
        dealer_product = dealer.dealer_products.new(
          product: product,
          product_variant: variant,
          stock_quantity: dealer_product_params[:stock_quantity],
          sell_in_b2b: sales_channel_param(:sell_in_b2b),
          sell_in_b2c: sales_channel_param(:sell_in_b2c),
          approve_status: status[:approve_status],
          is_active: status[:is_active]
        )
        dealer_product.save!
        if status[:approve_status] == :pending
          notify_admins_about_product_action(product.name, dealer.full_name, "submitted")
        end
        dealer_product
      end
    end

    def catalog_mapping?
      dealer_product_params[:product_id].present?
    end

    def submission_status
      if catalog_mapping? || current_admin
        { approve_status: :approved, is_active: true }
      else
        { approve_status: :pending, is_active: false }
      end
    end

    def dealer_product_creation_message
      if catalog_mapping?
        "Product mapped successfully and is now live"
      elsif current_admin
        "Dealer product mapped successfully"
      else
        "Dealer product created and sent for approval"
      end
    end

    def resolved_product_and_variant_for_submission
      if dealer_product_params[:product_id].present?
        product = Product.find(dealer_product_params[:product_id])
        variant =
          if dealer_product_params[:product_variant_id].present?
            product.product_variants.find(dealer_product_params[:product_variant_id])
          else
            product.product_variants.first || product.ensure_default_variant!
          end

        unless variant
          raise ActiveRecord::RecordInvalid.new(
            product.tap { |record| record.errors.add(:base, "Product pricing is required before mapping a dealer") }
          )
        end

        return [product, variant]
      end

      product_attrs = dealer_product_params[:product_attributes]
      raise ActiveRecord::RecordInvalid.new(DealerProduct.new.tap { |dp| dp.errors.add(:base, "Product details are required") }) if product_attrs.blank?

      normalized = normalize_product_submission_attributes(product_attrs.to_h.deep_dup)
      product = Product.new(normalized.merge("is_active" => false))
      product.save!

      variant = product.product_variants.first
      unless variant
        raise ActiveRecord::RecordInvalid.new(product.tap { |record| record.errors.add(:base, "At least one price set is required to create a dealer product") })
      end

      variant.update!(is_active: false)
      [product, variant]
    end

    def normalize_product_submission_attributes(attrs)
      variant_attrs = attrs["product_variants_attributes"]
      return attrs if variant_attrs.present?

      fallback_variant = build_fallback_variant_attributes(attrs)
      attrs["product_variants_attributes"] = [fallback_variant] if fallback_variant.present?
      attrs
    end

    def build_fallback_variant_attributes(attrs)
      variant_attrs = {}
      %w[variant_sku price selling_price dealer_price dealer_selling_price discount_percentage].each do |key|
        value = attrs.delete(key)
        variant_attrs[key] = value if value.present?
      end

      variant_attrs["variant_sku"] ||= default_variant_sku(attrs["sku"])
      return if variant_attrs.except("variant_sku").values.all?(&:blank?)

      variant_attrs["is_active"] = false
      variant_attrs
    end

    def default_variant_sku(product_sku)
      sku = product_sku.to_s.strip
      return "SKU-#{SecureRandom.hex(4).upcase}" if sku.blank?

      "#{sku}-DEFAULT"
    end

    def update_dealer_product_params
      attrs = dealer_product_params.slice(:stock_quantity, :sell_in_b2b, :sell_in_b2c).to_h
      attrs["sell_in_b2b"] = sales_channel_param(:sell_in_b2b) if dealer_product_params.key?(:sell_in_b2b)
      attrs["sell_in_b2c"] = sales_channel_param(:sell_in_b2c) if dealer_product_params.key?(:sell_in_b2c)
      attrs
    end

    def sales_channel_param(key)
      return true unless dealer_product_params.key?(key)

      ActiveModel::Type::Boolean.new.cast(dealer_product_params[key])
    end

    def set_dealer_product
      @dealer_product = DealerProduct.find_by(id: params[:id])
      render json: { error: "Dealer product not found" }, status: :not_found unless @dealer_product
    end

    def authorized_dealer_product_action?
      return true if current_user_type == "AdminUser"
      return false unless current_user_type == "Dealer"

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
