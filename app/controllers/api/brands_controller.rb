module Api
  class BrandsController < ApplicationController
    skip_before_action :authenticate_request!, only: [:index, :show]
    before_action :require_admin, except: [:index, :show]
    before_action :check_permission, except: [:index, :show]
    before_action :set_brand, only: [:show, :update, :destroy, :deactivate , :reactivate]
    
    def index
      brands = Brand.where(is_active: true).order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
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
      all_brands = Brand.all.order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      if all_brands.exists?
        render json: serialize_resource(all_brands, BrandSerializer).merge(
          meta: {
            current_page: all_brands.current_page,
            next_page: all_brands.next_page,
            prev_page: all_brands.prev_page,
            total_pages: all_brands.total_pages,
            total_count: all_brands.total_count
          },
          message: "All Brands fetched successfully" ), status: :ok
      else
        render json: { error: "Brands not found" }, status: :not_found
      end
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
      @brand.destroy
      render json: { message: "Brand deleted successfully" }, status: :ok
    end

    private

    def brand_params
      params.require(:brand).permit(:name, :slug, :is_active)
    end
    
    def set_brand
      @brand = Brand.find_by(id: params[:id])
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
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_created(email, "Brand", brand.name, current_admin&.email).deliver_later
      end
    end

    def notify_admins_entity_updated(brand)
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_updated(email, "Brand", brand.name, current_admin&.email).deliver_later
      end
    end
  end
end
