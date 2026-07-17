module Api
  class DealersController < ApplicationController
    skip_before_action :authenticate_request!, only: [:verify_otp, :resend_signup_otp]
    # before_action :authenticate_request!, except: [:verify_otp]
    before_action :require_admin, only: [:create, :index, :active_dealers, :block, :unblock, :destroy, :approve, :reject, :admin_overview]
    before_action :require_admin_approver!, only: [:approve, :reject]
    before_action :set_dealer, only: [:show, :update, :destroy, :block, :unblock, :approve, :reject, :verify_otp, :admin_overview]
    before_action :authorize_dealer_update, only: [:update, :show]

    def index
      dealers = Dealer.includes(:dealer_profile, :dealer_location)
      dealers = if current_admin.super_admin?
        Dealer.all
      else
        pincodes = current_admin.accessible_pincodes
        if pincodes.present?
          dealers = dealers.where(pincode: pincodes)
        else
          dealers = dealers.none
        end
      end

      dealers = dealers.where(status: params[:status]) if params[:status].present?
      dealers = dealers.where(pincode: params[:pincode]) if params[:pincode].present?
      dealers = dealers.where("first_name ILIKE ? OR last_name ILIKE ?", 
                               "%#{params[:search]}%", "%#{params[:search]}%") if params[:search].present?

      dealers = dealers.order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)

      render json: serialize_resource(dealers, DealerSerializer, base_url: request.base_url).merge(
        meta: {
          current_page: dealers.current_page,
          next_page: dealers.next_page,
          prev_page: dealers.prev_page,
          total_pages: dealers.total_pages,
          total_count: dealers.total_count
        },
        message: "Dealers fetched successfully"
      ), status: :ok
    end

    def active_dealers
      dealers = Dealer.includes(:dealer_profile, :dealer_location)

      unless current_admin.super_admin?
        pincodes = current_admin.accessible_pincodes
        dealers = pincodes.present? ? dealers.where(pincode: pincodes) : dealers.none
      end
      
      selected_status = params[:status].presence || "active"

      if selected_status != "all"
        unless Dealer.statuses.key?(selected_status)
          return render json: { error: "Invalid dealer status" }, status: :unprocessable_entity
        end

        dealers = dealers.where(status: selected_status)
      end

      dealers = dealers.order(created_at: :desc).page(params[:page]).per(params[:per_page] || 20)
      render json: serialize_resource(dealers, DealerSerializer, base_url: request.base_url).merge(
        meta: {
          current_page: dealers.current_page,
          next_page: dealers.next_page,
          prev_page: dealers.prev_page,
          total_pages: dealers.total_pages,
          total_count: dealers.total_count,
          statuses: ["all"] + Dealer.statuses.keys
        },
        message: "Dealers fetched successfully"
      ), status: :ok
    end

    def create
      if params[:dealer][:pincode].present?
        unless current_admin.can_access_pincode?(params[:dealer][:pincode])
          return render json: { error: "Access denied for pincode: #{params[:dealer][:pincode]}" }, status: :forbidden
        end
      end

      dealer = Dealer.new(dealer_params.except(:status))
      dealer.status = "pending"
      dealer.otp_pin = rand(1000..9999)
      dealer.otp_sent_at = Time.current

      unless dealer.email.present?
        return render json: { error: "Dealer email is required for OTP verification" }, status: :unprocessable_entity
      end

      if dealer.save
        DealerAuthMailer.signup_otp(dealer).deliver_later if dealer.email.present?
        notify_admins_about_dealer_creation(dealer)

        verify_url = "#{ENV['FRONTEND_URL'] || request.base_url}/dealer/signup-verify-otp?id=#{dealer.id}&email=#{CGI.escape(dealer.email)}"
        render json: serialize_resource(dealer, DealerSerializer, base_url: request.base_url).merge(
          message: "Dealer created successfully. OTP sent to dealer email.",
          verify_url: verify_url
        ), status: :created
      else
        render json: { error: dealer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def resend_signup_otp
      dealer = Dealer.find(params[:id])

      return render json: {
        error: "Dealer already verified"
      }, status: :unprocessable_entity if dealer.otp_pin.blank?

      dealer.update!(
        otp_pin: rand(1000..9999),
        otp_sent_at: Time.current
      )

      DealerAuthMailer.signup_otp(dealer).deliver_later

      render json: {
        message: "Signup OTP sent successfully"
      }
    end

    def show
      render json: serialize_resource(@dealer, DealerSerializer, base_url: request.base_url).merge(
        message: "Dealer fetched successfully"
      ), status: :ok
    end

    def admin_overview
      unless current_admin.can_access?(:dealers, :read)
        return render json: { error: "Access denied" }, status: :forbidden
      end

      unless dealer_accessible?(@dealer)
        return render json: { error: "Access denied for this dealer" }, status: :forbidden
      end

      payload = {
        dealer: serialize_data(@dealer, DealerSerializer, base_url: request.base_url),
        permissions: {
          dealers: current_admin.can_access?(:dealers, :read),
          dealer_products: current_admin.can_access?(:dealer_products, :read),
          wholesaler_posts: current_admin.can_access?(:wholesaler_posts, :read),
          orders: current_admin.can_access?(:orders, :read)
        }
      }

      if current_admin.can_access?(:dealer_products, :read)
        products = @dealer.dealer_products.includes(:product, :product_variant).order(created_at: :desc).limit(50)
        payload[:dealer_products] = products.map { |dp| dealer_product_summary(dp) }
        payload[:inventory_summary] = {
          total_products: @dealer.dealer_products.count,
          approved: @dealer.dealer_products.where(approve_status: "approved").count,
          pending: @dealer.dealer_products.where(approve_status: "pending").count,
          total_stock: @dealer.dealer_products.sum(:stock_quantity)
        }
      end

      if current_admin.can_access?(:wholesaler_posts, :read)
        posts = @dealer.wholesaler_posts.order(created_at: :desc).limit(20)
        payload[:wholesaler_posts] = posts.map { |p| wholesaler_post_summary(p) }
        payload[:wholesaler_posts_summary] = {
          total: @dealer.wholesaler_posts.count,
          pending: @dealer.wholesaler_posts.where(approve_status: "pending").count,
          approved: @dealer.wholesaler_posts.where(approve_status: "approved").count,
          rejected: @dealer.wholesaler_posts.where(approve_status: "rejected").count,
          expired: @dealer.wholesaler_posts.where("created_at < ?", 7.days.ago).count
        }
      end

      if current_admin.can_access?(:orders, :read)
        buyer_orders = @dealer.orders.includes(:seller_dealer, order_items: [:dealer_product]).order(created_at: :desc).limit(20)
        sales_orders = @dealer.sales_orders.includes(:buyer, order_items: [:dealer_product]).order(created_at: :desc).limit(20)
        b2b_buyer = @dealer.buyer_b2b_orders.includes(:seller_dealer).order(created_at: :desc).limit(20)
        b2b_seller = @dealer.seller_b2b_orders.includes(:buyer_dealer).order(created_at: :desc).limit(20)

        payload[:orders_as_buyer] = buyer_orders.map { |o| order_summary(o) }
        payload[:orders_as_seller] = sales_orders.map { |o| order_summary(o) }
        payload[:b2b_orders_as_buyer] = b2b_buyer.map { |o| b2b_order_summary(o) }
        payload[:b2b_orders_as_seller] = b2b_seller.map { |o| b2b_order_summary(o) }
      end

      render json: { data: payload, message: "Dealer overview fetched" }, status: :ok
    end

    def update
      if @dealer.update(dealer_params)
        notify_admins_entity_updated(@dealer)
        render json: serialize_resource(@dealer, DealerSerializer, base_url: request.base_url).merge(message: "Dealer updated successfully"), status: :ok
      else
        render json: {
          error: @dealer.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def block
      @dealer.update(status: "banned")
      notify_admins_entity_updated(@dealer)
      render json: { message: "Dealer blocked successfully" }, status: :ok
    end

    def unblock
      @dealer.update(status: "active")
      notify_admins_entity_updated(@dealer)
      render json: { message: "Dealer unblocked successfully" }, status: :ok
    end

    def approve
      unless @dealer.status == "pending"
        return render json: { error: "Dealer is already processed" }, status: :unprocessable_entity
      end

      if @dealer.otp_pin.present?
        return render json: { error: "Dealer must verify signup OTP before approval" }, status: :unprocessable_entity
      end

      unless current_admin.can_access_pincode?(@dealer.pincode)
        return render json: { error: "Access denied for pincode: #{@dealer.pincode}" }, 
                    status: :forbidden
      end

      if @dealer.update(status: "active")
        DealerMailer.approval_email(@dealer).deliver_later
        notify_admins_about_dealer_action(@dealer, "approved")

        render json: serialize_resource(@dealer, DealerSerializer, base_url: request.base_url).merge(
          message: "Dealer approved successfully. Approval email sent."
        ), status: :ok
      else
        render json: { error: @dealer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def reject
      unless @dealer.status == "pending"
        return render json: { error: "Dealer is already processed" }, status: :unprocessable_entity
      end

      unless current_admin.can_access_pincode?(@dealer.pincode)
        return render json: { error: "Access denied for pincode: #{@dealer.pincode}" }, status: :forbidden
      end

      rejection_reason = params[:reason] || "Application does not meet requirements"

      if @dealer.update(status: "rejected")
        DealerMailer.rejection_email(@dealer, rejection_reason).deliver_later
        notify_admins_about_dealer_action(@dealer, "rejected", rejection_reason)

        render json: serialize_resource(@dealer, DealerSerializer, base_url: request.base_url).merge(
          message: "Dealer rejected successfully. Rejection email sent."
        ), status: :ok
      else
        render json: { error: @dealer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def verify_otp
      unless @dealer.otp_valid?(params[:otp].to_s)
        return render json: { error: "Invalid or expired OTP" }, status: :unauthorized
      end

      temp_password = SecureRandom.hex(6)
      @dealer.update!(password: temp_password, password_confirmation: temp_password, otp_pin: nil, otp_sent_at: nil)
      DealerMailer.welcome_email(@dealer, temp_password).deliver_later if @dealer.email.present?
      notify_admins_about_dealer_approval(@dealer)

      render json: { message: "Dealer OTP verified successfully. Credentials have been emailed." }, status: :ok
    end

    def destroy
      return render json: {
        error: "Only super admin can delete dealers"
      }, status: :forbidden unless current_admin.super_admin?

      Dealer.transaction do      
        @dealer.update!(
          status: 'inactive',
          deleted_by: current_admin
        )

        @dealer.destroy
      end

      DeletionNotificationService.direct_deleted(@dealer, current_admin)
      DeletionMailService.direct_deleted(@dealer, current_admin)

      render json: {
        message: "Dealer deleted successfully"
      }
    end

    def nearby
      lat = params[:lat].to_f
      lng = params[:lng].to_f
      radius = params[:radius].to_f || 10
      limit = params[:limit].to_i || 20

      if lat.zero? || lng.zero?
        return render json: { error: "Latitude and longitude are required" }, status: :unprocessable_entity
      end

      results = Dealer.nearby(lat, lng, radius_km: radius, limit: limit)

      render json: {
        data: results,
        meta: {
          count: results.count,
          radius: radius,
          center: { latitude: lat, longitude: lng }
        }
      }, status: :ok
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
    
    private

    def dealer_params
      params.require(:dealer).permit(
        :first_name, :last_name, :email, :phone, :gender, :country_code, :status, :pincode, :password, :password_confirmation,
        dealer_profile_attributes: [
          :id, :business_name, :business_type, :gst_number, :pan_number, :aadhar_number,
          :bank_name, :bank_account_number, :ifsc_code, :business_address,
          :business_contact_number, :business_email, :work_category, :associated_brands,
          :is_verified, :pan_card, :gst_certificate, :cancel_cheque, { store_image: [], aadhar_card: [] }
        ],
        dealer_location_attributes: [:id, :latitude, :longitude, :service_radius_km, :is_active]
      )
    end

    def set_dealer
      @dealer = Dealer.find_by(id: params[:id])
      render json: { error: "Dealer not found" }, status: :not_found unless @dealer
    end

    def require_admin
      render json: { error: "Admin only" }, status: :unauthorized unless current_user_type == "AdminUser"
    end

    def authorize_dealer_update
      # allow admin or the dealer themselves to view/update profile
      return if current_user_type == "AdminUser"
      if current_user_type == "Dealer" && current_user.id == @dealer.id
        return
      end
      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def get_admin_emails
      AdminUser.active.select { |admin| admin.approver_admin? && admin.email.present? }.map(&:email)
    end

    def notify_admins_about_dealer_creation(dealer)
      admin_emails = get_admin_emails
      admin_emails.each do |email|
        AdminNotificationMailer.dealer_action(email, dealer.full_name, "created", "New dealer registered").deliver_later
      end
    end

    def notify_admins_about_dealer_approval(dealer)
      approvers = AdminUser.where(status: "active")
      approvers.find_each do |admin|
        next if admin.email.blank?
        next unless admin.approver_admin?

        DealerAuthMailer.onboarding_approval_request(dealer, admin.email).deliver_later
      end
    end

    def notify_admins_about_dealer_action(dealer, action, details = nil)
      admin_emails = get_admin_emails
      admin_emails.each do |email|
        AdminNotificationMailer.dealer_action(email, dealer.full_name, action, details).deliver_later
      end
    end

    def notify_admins_entity_updated(dealer)
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_updated(email, "Dealer", dealer.full_name, current_admin&.email).deliver_later
      end
    end

    def require_admin_approver!
      return if current_admin&.approver_admin?
      render json: { error: "Only Super Admin or Sub Admin can approve dealer onboarding" }, status: :forbidden
    end

    def dealer_accessible?(dealer)
      return true if current_admin.super_admin?
      current_admin.can_access_pincode?(dealer.pincode)
    end

    def dealer_product_summary(dp)
      {
        id: dp.id,
        product_name: dp.product&.name,
        sku: dp.product_variant&.variant_sku || dp.product&.sku,
        stock_quantity: dp.stock_quantity,
        approve_status: dp.approve_status,
        is_active: dp.is_active,
        selling_price: dp.product_variant&.dealer_selling_price,
        created_at: dp.created_at
      }
    end

    def wholesaler_post_summary(post)
      {
        id: post.id,
        title: post.title,
        approve_status: post.approve_status,
        is_expired: !post.visible_to_others?,
        price: post.price,
        stock_quantity: post.stock_quantity,
        created_at: post.created_at
      }
    end

    def order_summary(order)
      {
        id: order.id,
        order_number: order.order_number,
        status: order.status,
        total_amount: order.total_amount.to_f,
        payment_method: order.payment_method,
        payment_status: order.payment_status,
        created_at: order.created_at,
        items_count: order.order_items.size
      }
    end

    def b2b_order_summary(order)
      {
        id: order.id,
        status: order.status,
        total_amount: order.total_amount.to_f,
        payment_method: order.payment_method,
        payment_status: order.payment_status,
        created_at: order.created_at,
        buyer_dealer_id: order.buyer_dealer_id,
        seller_dealer_id: order.seller_dealer_id
      }
    end

    def current_admin
      current_user
    end
  end
end
