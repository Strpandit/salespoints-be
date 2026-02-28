module Api
  class CategoriesController < ApplicationController
    skip_before_action :authenticate_request!, only: [:index, :show]
    before_action :require_admin, except: [:index, :show]
    before_action :check_permission, except: [:index, :show]
    before_action :set_category, only: [:show, :update, :deactivate, :reactivate]

    def index
      if params[:slug].present?
        category = Category.find_by(slug: params[:slug])
        if category
          render json: { data: CategorySerializer.new(category), message: "Category fetched" }, status: :ok
        else
          render json: { error: "Category not found" }, status: :not_found
        end
      else
        categories = Category.where(is_active: true)
        if categories.exists?
          render json: { data: ActiveModelSerializers::SerializableResource.new(categories, each_serializer: CategorySerializer), message: "Categories fetched successfully" }, status: :ok
        else
          render json: { error: "No categories found" }, status: :not_found
        end
      end
    end

    def all_categories
      categories = Category.all
      if categories.exists?
        render json: { data: ActiveModelSerializers::SerializableResource.new(categories, each_serializer: CategorySerializer), message: "Categories fetched successfully" }, status: :ok
      else
        render json: { error: "No categories found" }, status: :not_found
      end
    end

    def show
      if @category.exists?
        render json: { data: CategorySerializer.new(@category), message: "Category details fetched successfully" }, status: :ok
      else
        render json: { error: "Category not found" }, status: :not_found
      end
    end

    def create
      category = Category.new(category_params)
      if category.save
        notify_admins_entity_created(category)
        render json: {data: CategorySerializer.new(category), message: "Category created successfully"}, status: :created
      else
        render json: { error: category.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @category.update(category_params)
        notify_admins_entity_updated(@category)
        render json: {data: CategorySerializer.new(@category), message: "Category updated successfully"}, status: :ok
      else
        render json: { error: category.errors.full_messages }, status: :unprocessable_entity
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

    private

    def category_params
      params.require(:category).permit(:name, :slug, :is_active)
    end

    def set_category
      @category = Category.find_by(id: params[:id])
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
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_created(email, "Category", category.name, current_admin&.email).deliver_later
      end
    end

    def notify_admins_entity_updated(category)
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_updated(email, "Category", category.name, current_admin&.email).deliver_later
      end
    end
  end
end
