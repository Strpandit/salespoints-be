module Api
  class ProductsController < ApplicationController
    skip_before_action :authenticate_request!, only: [:index, :active_products, :show, :similar_product]
    before_action :require_admin, except: [:index, :active_products, :show, :similar_product]
    before_action :check_permission, except: [:index, :active_products, :show, :similar_product]
    before_action :find_product, only: [:show, :update, :destroy]

    def index
      products = Product.includes(:category, :brand, :product_variants)

      if params[:category_id].present? && params[:category_id] != "all"
        products = products.where(category_id: params[:category_id])
      end

      if params[:brand_id].present? && params[:brand_id] != "all"
        products = products.where(brand_id: params[:brand_id])
      end

      if params[:is_active].present? && params[:is_active] != "all"
        is_act = ActiveModel::Type::Boolean.new.cast(params[:is_active])
        products = products.where(is_active: is_act)
      end

      if params[:search].present?
        q = "%#{params[:search].strip}%"
        products = products.joins("LEFT JOIN product_variants ON product_variants.product_id = products.id")
                           .where("products.name ILIKE :q OR products.sku ILIKE :q OR products.hsn_code ILIKE :q OR product_variants.variant_name ILIKE :q OR product_variants.sku ILIKE :q", q: q)
                           .distinct
      end

      case params[:sort_by]
      when "oldest"
        products = products.order("products.created_at ASC")
      when "name_asc"
        products = products.order("products.name ASC")
      when "name_desc"
        products = products.order("products.name DESC")
      else
        products = products.order("products.created_at DESC")
      end

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

    def active_products
      products = Product.active.includes(:category, :brand, :product_variants)

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
      render json: serialize_resource(@product, ProductSerializer, base_url: request.base_url).merge(
        message: "Product fetched successfully"
      ), status: :ok
    end

    def similar_product
      products = Product.active.where(category_id: params[:category_id])
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
        :is_featured, :is_new, :is_active, :tax_rate, :hsn_code,
        :price, :selling_price, :dealer_price, :dealer_selling_price, :discount_percentage,
        :primary_media_blob_id, :primary_new_media_index,
        :purge_media_blob_ids, { purge_media_blob_ids: [] },
        media: [],
        features: [], care_instructions: [],
        product_specifications_attributes: [:id, :key, :value, :_destroy],
        product_variants_attributes: [
          :id, :variant_sku, :price, :selling_price, :dealer_price, :hsn_code,
          :dealer_selling_price, :discount_percentage, :is_active, :_destroy,
          :primary_media_blob_id, :primary_new_media_index,
          :purge_media_blob_ids, { purge_media_blob_ids: [] },
          { media: [], variant_attributes: [:key, :value], product_variant_colors_attributes: [:id, :color_name, :color_hex, :_destroy] }
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
        blob_ids.concat(Array(product_blob_ids))
      end

      variants = params.dig(:product, :product_variants_attributes)
      if variants.present?
        variants.each do |_index, attrs|
          if attrs.is_a?(ActionController::Parameters)
            attrs = attrs.to_unsafe_h
          end

          variant_blob_ids = attrs["purge_media_blob_ids"] || attrs[:purge_media_blob_ids]
          if variant_blob_ids.present?
            blob_ids.concat(Array(variant_blob_ids))
          end
        end
      end

      blob_ids.map(&:to_i).reject(&:zero?).uniq
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
        blob_ids = []

        if attrs["purge_media_blob_ids"].present?
          blob_ids.concat(Array(attrs["purge_media_blob_ids"]))
        end

        if attrs[:purge_media_blob_ids].present?
          blob_ids.concat(Array(attrs[:purge_media_blob_ids]))
        end

        blob_ids = blob_ids.map(&:to_i).reject(&:zero?).uniq

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
        record.update_column(:primary_media_blob_id, remaining&.blob_id)
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
      details = product.attributes.except("id", "created_at", "updated_at", "primary_media_blob_id")
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_created(email, "Product", product.name, current_admin, details).deliver_later
      end
    end

    def notify_admins_entity_updated(product)
      changes = product.saved_changes.except("updated_at", "created_at").transform_values { |v| { from: v[0], to: v[1] } }
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_updated(email, "Product", product.name, current_admin, changes).deliver_later
      end
    end

    def notify_admins_entity_deleted(product)
      details = product.attributes.except("id", "created_at", "updated_at")
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_deleted(email, "Product", product.name, current_admin, details).deliver_later
      end
    end
  end
end
