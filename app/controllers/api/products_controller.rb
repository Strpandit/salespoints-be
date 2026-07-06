module Api
  class ProductsController < ApplicationController
    skip_before_action :authenticate_request!, only: [:index, :active_products, :show, :similar_product]
    before_action :require_admin, except: [:index, :active_products, :show, :similar_product]
    before_action :check_permission, except: [:index, :active_products, :show, :similar_product]
    before_action :find_product, only: [:show, :update, :destroy]

    def index
      products = Product.all.order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      render json: serialize_resource(products, ProductSerializer, base_url: request.base_url).merge(
        meta: {
          current_page: products.current_page,
          next_page: products.next_page,
          prev_page: products.prev_page,
          total_pages: products.total_pages,
          total_count: products.total_count
        },
        message: "Products fetched successfully"
      ), status: :ok
    end

    def active_products
      products = Product.active_in_stock.includes(:category, :brand, :product_variants)

      if params[:category_id].present?
        products = products.where(category_id: params[:category_id])
      end

      if params[:search].present?
        query = params[:search].strip
        products = products.where("products.name ILIKE ?", "%#{query}%")
      end

      products = apply_active_product_sort(products, params[:sort])
      products = products.page(params[:page]).per(params[:per_page] || 20)

      render json: serialize_resource(products, ProductSerializer, base_url: request.base_url).merge(
        meta: {
          current_page: products.current_page,
          next_page: products.next_page,
          prev_page: products.prev_page,
          total_pages: products.total_pages,
          total_count: products.total_count
        },
        message: "Products fetched successfully"
      ), status: :ok
    end

    def show
      unless @product.stock_quantity.to_i > 0
        return render json: { error: "Product is out of stock" }, status: :not_found
      end

      render json: serialize_resource(@product, ProductSerializer, base_url: request.base_url).merge(
        message: "Product fetched successfully"
      ), status: :ok
    end

    def similar_product
      products = Product.active_in_stock.where(category_id: params[:category_id])
                        .where.not(id: params[:product_id])
                        .limit(4)
    
      if products.present?
        render json: serialize_resource(products, ProductSerializer, base_url: request.base_url).merge(
          message: "Similar products fetched successfully"
        ), status: :ok
      else
        render json: { errors: "No similar products found" }, status: :not_found
      end
    end

    def create
      product = Product.new(normalized_product_params)

      if product.save
        notify_admins_entity_created(product)
        render json: serialize_resource(product, ProductSerializer, base_url: request.base_url).merge(
          message: "Product created successfully"
        ), status: :created
      else
        render json: { error: product.errors.full_messages }, status: :unprocessable_entity
      end
    end

  def update
    purge_blob_ids = extract_purge_blob_ids
    variant_purge_map = extract_variant_purge_blob_ids

    if @product.update(normalized_product_params)
      purge_media_blobs!(@product, purge_blob_ids)
      apply_variant_media_purges!(variant_purge_map)
      notify_admins_entity_updated(@product)
        render json: serialize_resource(@product, ProductSerializer, base_url: request.base_url).merge(
          message: "Product updated successfully"
        ), status: :ok
      else
        render json: { error: @product.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @product.update(deleted_at: Time.current, is_active: false, is_featured: false, is_new: false)
      @product.product_variants.update_all(is_active: false)
      notify_admins_entity_deleted(@product)
      render json: { message: "Product deleted successfully" }, status: :ok
    end

    private

    VARIANT_FIELD_KEYS = %i[
      variant_sku
      price
      selling_price
      dealer_price
      dealer_selling_price
      discount_percentage
      is_active
      variant_attributes
    ].freeze

    def product_params
      params.require(:product).permit(
        :name, :slug, :sku, :desc, :material, :brand_id, :category_id,
        :is_featured, :is_new, :is_active, :tax_rate,
        :price, :selling_price, :dealer_price, :dealer_selling_price, :discount_percentage,
        :stock_quantity, :primary_media_blob_id, :primary_new_media_index,
        { purge_media_blob_ids: [] },
        media: [],
        features: [], care_instructions: [],
        product_specifications_attributes: [:id, :key, :value, :_destroy],
        product_variants_attributes: [
          :id, :variant_sku, :price, :selling_price, :dealer_price,
          :dealer_selling_price, :discount_percentage, :is_active, :_destroy,
          :primary_media_blob_id, :primary_new_media_index,
          { purge_media_blob_ids: [] },
          { media: [], variant_attributes: [:key, :value] }
        ]
      )
    end

    def normalized_product_params
      attrs = product_params.to_h.deep_dup
      variant_attrs = attrs["product_variants_attributes"]
      return attrs if variant_attrs.present?
      return attrs if @product&.product_variants&.exists?

      fallback_variant = build_fallback_variant_attributes(attrs)
      return attrs if fallback_variant.blank?

      attrs["product_variants_attributes"] = [fallback_variant]
      attrs
    end

    def build_fallback_variant_attributes(attrs)
      variant_attrs = {}
      VARIANT_FIELD_KEYS.each do |key|
        value = attrs.delete(key.to_s)
        variant_attrs[key.to_s] = value if value.present?
      end

      variant_attrs["variant_sku"] ||= generated_default_variant_sku(attrs["sku"])
      return if variant_attrs.except("variant_sku", "is_active").values.all?(&:blank?)

      variant_attrs["is_active"] = true if variant_attrs["is_active"].nil?
      variant_attrs
    end

    def generated_default_variant_sku(product_sku)
      sku = product_sku.to_s.strip
      return if sku.blank?

      "#{sku}-DEFAULT"
    end

    def apply_active_product_sort(scope, sort)
      case sort
      when "price_asc"
        scope.left_joins(:product_variants)
             .group("products.id")
             .order(Arel.sql("MIN(product_variants.selling_price) ASC NULLS LAST"))
      when "price_desc"
        scope.left_joins(:product_variants)
             .group("products.id")
             .order(Arel.sql("MIN(product_variants.selling_price) DESC NULLS LAST"))
      else
        scope.order(created_at: :desc)
      end
    end

    def find_product
      @product = Product.find_by(id: params[:id]) || Product.find_by(slug: params[:id])
      render json: { error: "Product not found" }, status: :not_found unless @product
    end

    def check_permission
      unless current_admin.can_access?(:products)
        render json: { error: "You do not have permission to manage products"}, status: :forbidden
      end
    end

    def require_admin
      render json: { error: "Admin only" }, status: :unauthorized unless current_user_type == "AdminUser"
    end

    def current_admin
      current_user
    end

    def extract_purge_blob_ids
      blob_ids = []

      product_blob_ids = params.dig(:product, :purge_media_blob_ids)
      if product_blob_ids.present?
        blob_ids.concat(Array(product_blob_ids).map(&:to_i))
      end

      variants = params.dig(:product, :product_variants_attributes)
      if variants.present?
        variants.each do |_index, attrs|
          if attrs.is_a?(ActionController::Parameters)
            attrs = attrs.to_unsafe_h
          end

          variant_blob_ids = attrs["purge_media_blob_ids"] || attrs[:purge_media_blob_ids]
          if variant_blob_ids.present?
            blob_ids.concat(Array(variant_blob_ids).map(&:to_i))
          end
        end
      end

      blob_ids.reject(&:zero?).uniq
    end

    def extract_variant_purge_blob_ids
      variants = params.dig(:product, :product_variants_attributes)
      return {} if variants.blank?

      variants = variants.to_unsafe_h if variants.is_a?(ActionController::Parameters)

      map = {}

      variants.each do |_index, attrs|
        attrs = attrs.to_unsafe_h if attrs.is_a?(ActionController::Parameters)

        variant_id = attrs["id"] || attrs[:id]
        next if variant_id.blank?

        blob_ids = Array(attrs["purge_media_blob_ids"] || attrs[:purge_media_blob_ids])
                    .map(&:to_i)
                    .reject(&:zero?)

        map[variant_id.to_i] = blob_ids if blob_ids.any?
      end

      map
    end

    def purge_media_blobs!(record, blob_ids)
      return if blob_ids.blank?

       record.media_attachments.each do |attachment|
        if blob_ids.include?(attachment.blob_id)
          attachment.purge
        end
      end
      if blob_ids.include?(record.primary_media_blob_id)
        remaining = record.media_attachments.first
        record.update_column(:primary_media_blob_id, nil)
      end
    end

    def apply_variant_media_purges!(variant_purge_map)
      variant_purge_map.each do |variant_id, blob_ids|
        variant = @product.product_variants.find_by(id: variant_id)
        purge_media_blobs!(variant, blob_ids) if variant
      end
    end

    ### notification helpers
    def get_admin_emails
      AdminUser.where(is_super_admin: true).pluck(:email)
    end

    def notify_admins_entity_created(product)
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_created(email, "Product", product.name, current_admin&.email).deliver_later
      end
    end

    def notify_admins_entity_updated(product)
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_updated(email, "Product", product.name, current_admin&.email).deliver_later
      end
    end

    def notify_admins_entity_deleted(product)
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_deleted(email, "Product", product.name, current_admin&.email).deliver_later
      end
    end
  end
end
