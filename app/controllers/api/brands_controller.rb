module Api
  class BrandsController < ApplicationController
    skip_before_action :authenticate_request!, only: [:index, :show]
    before_action :require_admin, except: [:index, :show]
    before_action :check_permission, except: [:index, :show]
    before_action :set_brand, only: [:show, :update, :destroy, :deactivate , :reactivate]
    
    def index
      brands = Brand.includes(:categories).where(is_active: true).order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      if brands.exists?
        render json: serialize_resource(brands, BrandSerializer).merge(
          meta: {
            current_page: brands.current_page,
            next_page: brands.next_page,
            prev_page: brands.prev_page,
            total_pages: brands.total_pages,
            total_count: brands.total_count
          },
          message: "Brands fetched successfully" ), status: :ok
      else
        render json: { error: "No brands found" }, status: :not_found
      end
    end

    def all_brands
      all_brands = Brand.includes(:categories)

      if params[:is_active].present? && params[:is_active] != "all"
        is_act = ActiveModel::Type::Boolean.new.cast(params[:is_active])
        all_brands = all_brands.where(is_active: is_act)
      end

      if params[:category_id].present? && params[:category_id] != "all"
        all_brands = all_brands.joins(:categories).where(categories: { id: params[:category_id] })
      end

      if params[:search].present?
        q = "%#{params[:search].strip}%"
        all_brands = all_brands.where("name ILIKE ?", q)
      end

      case params[:sort_by]
      when "oldest"
        all_brands = all_brands.order(created_at: :asc)
      when "name_asc"
        all_brands = all_brands.order(name: :asc)
      when "name_desc"
        all_brands = all_brands.order(name: :desc)
      else
        all_brands = all_brands.order(created_at: :desc)
      end

      all_brands = all_brands.page(params[:page]).per(params[:per_page] || 20)

      render json: serialize_resource(all_brands, BrandSerializer).merge(
        meta: {
          current_page: all_brands.current_page,
          next_page: all_brands.next_page,
          prev_page: all_brands.prev_page,
          total_pages: all_brands.total_pages,
          total_count: all_brands.total_count
        },
        message: "All Brands fetched successfully"
      ), status: :ok
    end

    def show
      if @brand.present?
        render json: serialize_resource(@brand, BrandSerializer).merge(message: "Brand details fetched successfully"), status: :ok
      else
        render json: { error: "Brand not found" }, status: :not_found
      end
    end

    def create
      brand = Brand.new(brand_params)
      if brand.save
        notify_admins_entity_created(brand)
        render json: serialize_resource(brand, BrandSerializer).merge(message: "Brand created successfully"), status: :created
      else
        render json: { error: brand.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @brand.update(brand_params)
        notify_admins_entity_updated(@brand)
        render json: serialize_resource(@brand, BrandSerializer).merge(message: "Brand updated successfully"), status: :ok
      else
        render json: { error: @brand.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def deactivate
      @brand.update(is_active: false)
      render json: { message: "Brand deactivated successfully" }
    end

    def reactivate
      @brand.update(is_active: true)
      render json: { message: "Brand reactivated successfully" }
    end

    def destroy
      notify_admins_entity_deleted(@brand)
      @brand.destroy
      render json: { message: "Brand deleted successfully" }, status: :ok
    end

    private

    def brand_params
      params.require(:brand).permit(:name, :slug, :is_active, category_ids: [])
    end
    
    def set_brand
      @brand = Brand.includes(:categories).find_by(id: params[:id])
      render json: { error: "Brand not found" }, status: :not_found unless @brand
    end

    def check_permission
      unless current_admin.can_access?(:brands)
        render json: { error: "You do not have permission to manage brands"}, status: :forbidden
      end
    end

    def require_admin
      render json: { error: "Admin only" }, status: :unauthorized unless current_user_type == "AdminUser"
    end

    def current_admin
      current_user
    end

    ### notification helpers
    def get_admin_emails
      AdminUser.where(is_super_admin: true).pluck(:email)
    end

    def notify_admins_entity_created(brand)
      details = brand.attributes.except("id", "created_at", "updated_at")
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_created(email, "Brand", brand.name, current_admin, details).deliver_later
      end
    end

    def notify_admins_entity_updated(brand)
      changes = brand.saved_changes.except("updated_at", "created_at").transform_values { |v| { from: v[0], to: v[1] } }
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_updated(email, "Brand", brand.name, current_admin, changes).deliver_later
      end
    end

    def notify_admins_entity_deleted(brand)
      details = brand.attributes.except("id", "created_at", "updated_at")
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_deleted(email, "Brand", brand.name, current_admin, details).deliver_later
      end
    end
  end
end
