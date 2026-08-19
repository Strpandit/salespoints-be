module Api
  class CategoriesController < ApplicationController
    skip_before_action :authenticate_request!, only: [:index, :show]
    before_action :require_admin, except: [:index, :show]
    before_action :check_permission, except: [:index, :show]
    before_action :set_category, only: [:show, :update, :deactivate, :reactivate, :destroy]

    def index
      if params[:slug].present?
        category = Category.find_by(slug: params[:slug])
        if category
          render json: serialize_resource(category, CategorySerializer, base_url: request.base_url).merge(message: "Category fetched"), status: :ok
        else
          render json: { error: "Category not found" }, status: :not_found
        end
      else
        categories = Category.includes(:brands).where(is_active: true).order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
        if categories.exists?
          render json: serialize_resource(categories, CategorySerializer, base_url: request.base_url).merge(
            meta: {
              current_page: categories.current_page,
              next_page: categories.next_page,
              prev_page: categories.prev_page,
              total_pages: categories.total_pages,
              total_count: categories.total_count
            },
            message: "Categories fetched successfully" ), status: :ok
        else
          render json: { error: "No categories found" }, status: :not_found
        end
      end
    end

    def all_categories
      categories = Category.includes(:brands)

      if params[:is_active].present? && params[:is_active] != "all"
        is_act = ActiveModel::Type::Boolean.new.cast(params[:is_active])
        categories = categories.where(is_active: is_act)
      end

      if params[:search].present?
        q = "%#{params[:search].strip}%"
        categories = categories.where("name ILIKE :q OR slug ILIKE :q", q: q)
      end

      case params[:sort_by]
      when "oldest"
        categories = categories.order(created_at: :asc)
      when "name_asc"
        categories = categories.order(name: :asc)
      when "name_desc"
        categories = categories.order(name: :desc)
      else
        categories = categories.order(created_at: :desc)
      end

      categories = categories.page(params[:page]).per(params[:per_page] || 20)

      render json: serialize_resource(categories, CategorySerializer, base_url: request.base_url).merge(
        meta: {
          current_page: categories.current_page,
          next_page: categories.next_page,
          prev_page: categories.prev_page,
          total_pages: categories.total_pages,
          total_count: categories.total_count
        },
        message: "Categories fetched successfully"
      ), status: :ok
    end

    def show
      if @category.present?
        render json: serialize_resource(@category, CategorySerializer, base_url: request.base_url ).merge(message: "Category details fetched successfully"), status: :ok
      else
        render json: { error: "Category not found" }, status: :not_found
      end
    end

    def create
      category = Category.new(category_params)
      if category.save
        notify_admins_entity_created(category)
        render json: serialize_resource(category, CategorySerializer, base_url: request.base_url).merge(message: "Category created successfully"), status: :created
      else
        render json: { error: category.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @category.update(category_params)
        notify_admins_entity_updated(@category)
        render json: serialize_resource(@category, CategorySerializer, base_url: request.base_url).merge(message: "Category updated successfully"), status: :ok
      else
        render json: { error: @category.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def deactivate
      @category.update(is_active: false)
      render json: { message: "Category deactivated successfully" }
    end

    def reactivate
      @category.update(is_active: true)
      render json: { message: "Category reactivated successfully" }
    end

    def destroy
      if @category.products.exists?
        render json: {
          error: "Cannot delete category because products are present in this category"
        }, status: :unprocessable_entity
        return
      end

      notify_admins_entity_deleted(@category)
      if @category.destroy
        render json: { message: "Category deleted successfully" }, status: :ok
      else
        render json: {
          error: @category.errors.full_messages.join(", ")
        }, status: :unprocessable_entity
      end
    end

    private

    def category_params
      params.require(:category).permit(:name, :slug, :is_active, :cat_icon, brand_ids: [])
    end

    def set_category
      @category = Category.includes(:brands).find_by(id: params[:id])
      render json: { error: "Category not found" }, status: :not_found unless @category
    end

    def check_permission
      unless current_admin.can_access?(:categories)
        render json: { error: "You do not have permission to manage categories"}, status: :forbidden
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

    def notify_admins_entity_created(category)
      details = category.attributes.except("id", "created_at", "updated_at")
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_created(email, "Category", category.name, current_admin, details).deliver_later
      end
    end

    def notify_admins_entity_updated(category)
      changes = category.saved_changes.except("updated_at", "created_at").transform_values { |v| { from: v[0], to: v[1] } }
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_updated(email, "Category", category.name, current_admin, changes).deliver_later
      end
    end

    def notify_admins_entity_deleted(category)
      details = category.attributes.except("id", "created_at", "updated_at")
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_deleted(email, "Category", category.name, current_admin, details).deliver_later
      end
    end
  end
end
