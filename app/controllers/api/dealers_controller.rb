module Api
  class DealersController < ApplicationController
    skip_before_action :authenticate_request!, only: [:verify_otp, :resend_signup_otp, :check_signup_token]
    # before_action :authenticate_request!, except: [:verify_otp]
    before_action :require_admin, only: [:create, :index, :active_dealers, :block, :unblock, :destroy, :approve, :reject, :admin_overview]
    before_action :require_admin_approver!, only: [:approve, :reject]
    before_action :set_dealer, only: [:show, :update, :destroy, :block, :unblock, :approve, :reject, :admin_overview, :verify_bank_account]
    before_action :authorize_dealer_update, only: [:update, :show, :verify_bank_account]

    def check_signup_token
      dealer = find_signup_dealer
      unless dealer
        return render json: { valid: false, error: "Verification link or token is invalid.", verified_or_expired: true }, status: :unprocessable_entity
      end

      if dealer.signup_token.blank? || dealer.otp_pin.blank?
        return render json: { valid: false, error: "This signup verification link has already been used or verified. Please log in.", verified_or_expired: true }, status: :unprocessable_entity
      end

      unless dealer.token_valid?(params[:token] || dealer.signup_token)
        return render json: { valid: false, error: "Verification link has expired (10 min limit). Please request a new OTP.", verified_or_expired: true }, status: :unprocessable_entity
      end

      render json: { valid: true, email: dealer.email, id: dealer.id }
    end

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

      if params[:status].present? && params[:status] != "all"
        dealers = dealers.where(status: params[:status])
      end

      if params[:is_active].present? && params[:is_active] != "all"
        is_act = ActiveModel::Type::Boolean.new.cast(params[:is_active])
        dealers = dealers.left_outer_joins(:dealer_location).where(
          "dealers.status = :act_status OR dealer_locations.is_active = :is_act",
          act_status: is_act ? "active" : "inactive",
          is_act: is_act
        )
      end

      if params[:pincode].present?
        dealers = dealers.where(pincode: params[:pincode])
      end

      if params[:state].present? && params[:state] != "all"
        dealers = dealers.where("state ILIKE ?", "%#{params[:state]}%")
      end

      if params[:city].present? && params[:city] != "all"
        dealers = dealers.where("city ILIKE ?", "%#{params[:city]}%")
      end

      if params[:date_from].present?
        from = Date.parse(params[:date_from]).beginning_of_day rescue nil
        dealers = dealers.where("created_at >= ?", from) if from
      end

      if params[:date_to].present?
        to = Date.parse(params[:date_to]).end_of_day rescue nil
        dealers = dealers.where("created_at <= ?", to) if to
      end

      if params[:search].present?
        q = "%#{params[:search].strip}%"
        dealers = dealers.left_outer_joins(:dealer_profile).where(
          "dealers.first_name ILIKE :q OR dealers.last_name ILIKE :q OR dealers.email ILIKE :q OR dealers.phone ILIKE :q OR dealers.dealer_code ILIKE :q OR dealer_profiles.company_name ILIKE :q OR dealer_profiles.gst_number ILIKE :q",
          q: q
        ).distinct
      end

      case params[:sort_by]
      when "oldest"
        dealers = dealers.reorder("dealers.created_at ASC")
      when "name_asc"
        dealers = dealers.reorder("dealers.first_name ASC, dealers.last_name ASC")
      when "name_desc"
        dealers = dealers.reorder("dealers.first_name DESC, dealers.last_name DESC")
      else
        dealers = dealers.reorder("dealers.created_at DESC")
      end

      dealers = dealers.page(params[:page]).per(params[:per_page] || 20)

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
      
      selected_status = params[:status].presence

      if selected_status.present? && selected_status != "all"
        dealers = dealers.where(status: selected_status) if Dealer.statuses.key?(selected_status)
      end

      if params[:is_active].present? && params[:is_active] != "all"
        is_act = ActiveModel::Type::Boolean.new.cast(params[:is_active])
        dealers = dealers.left_outer_joins(:dealer_location).where(
          "dealers.status = :act_status OR dealer_locations.is_active = :is_act",
          act_status: is_act ? "active" : "inactive",
          is_act: is_act
        )
      end

      if params[:pincode].present?
        dealers = dealers.where(pincode: params[:pincode])
      end

      if params[:state].present? && params[:state] != "all"
        dealers = dealers.where("state ILIKE ?", "%#{params[:state]}%")
      end

      if params[:city].present? && params[:city] != "all"
        dealers = dealers.where("city ILIKE ?", "%#{params[:city]}%")
      end

      if params[:date_from].present?
        from = Date.parse(params[:date_from]).beginning_of_day rescue nil
        dealers = dealers.where("created_at >= ?", from) if from
      end

      if params[:date_to].present?
        to = Date.parse(params[:date_to]).end_of_day rescue nil
        dealers = dealers.where("created_at <= ?", to) if to
      end

      if params[:search].present?
        q = "%#{params[:search].strip}%"
        dealers = dealers.left_outer_joins(:dealer_profile).where(
          "dealers.first_name ILIKE :q OR dealers.last_name ILIKE :q OR dealers.email ILIKE :q OR dealers.phone ILIKE :q OR dealers.dealer_code ILIKE :q OR dealer_profiles.business_name ILIKE :q OR dealer_profiles.gst_number ILIKE :q",
          q: q
        ).distinct
      end

      case params[:sort_by]
      when "oldest"
        dealers = dealers.reorder("dealers.created_at ASC")
      when "name_asc"
        dealers = dealers.reorder("dealers.first_name ASC, dealers.last_name ASC")
      when "name_desc"
        dealers = dealers.reorder("dealers.first_name DESC, dealers.last_name DESC")
      else
        dealers = dealers.reorder("dealers.created_at DESC")
      end

      dealers = dealers.page(params[:page]).per(params[:per_page] || 20)
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

      unless dealer.email.present?
        return render json: { error: "Dealer email is required for OTP verification" }, status: :unprocessable_entity
      end

      if dealer.save
        token = dealer.generate_signup_token!
        DealerAuthMailer.signup_otp(dealer).deliver_later if dealer.email.present?
        notify_admins_about_dealer_creation(dealer)

        verify_url = "#{ENV['FRONTEND_URL'] || request.base_url}/dealer/signup-verify-otp?token=#{token}"
        render json: serialize_resource(dealer, DealerSerializer, base_url: request.base_url).merge(
          message: "Dealer created successfully. 6-digit OTP sent to dealer email.",
          verify_url: verify_url,
          token: token
        ), status: :created
      else
        render json: { error: dealer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def resend_signup_otp
      dealer = find_signup_dealer || Dealer.find_by(id: params[:id])
      unless dealer
        return render json: { error: "Dealer not found" }, status: :not_found
      end

      if dealer.signup_token.blank? && dealer.otp_pin.blank?
        return render json: { error: "Dealer already verified. Please log in.", verified_or_expired: true }, status: :unprocessable_entity
      end

      new_token = dealer.generate_signup_token!
      DealerAuthMailer.signup_otp(dealer).deliver_later

      render json: { message: "Signup OTP & Agreement sent successfully", token: new_token }
    end

    def show
      render json: serialize_resource(@dealer, DealerSerializer, base_url: request.base_url).merge(
        message: "Dealer fetched successfully"
      ), status: :ok
    end

    def profile
      dealer = current_dealer
      unless dealer
        return render json: { error: "Dealer not found" }, status: :not_found
      end

      render json: serialize_resource(dealer, DealerSerializer, base_url: request.base_url).merge(
        message: "Dealer profile fetched successfully"
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
      normalize_verified_bank_payload!

      profile_before = @dealer.dealer_profile&.attributes || {}
      location_before = @dealer.dealer_location&.attributes || {}

      if @dealer.update(dealer_params)
        is_dealer_user = current_user_type == "Dealer"

        if is_dealer_user
          dealer_changes = @dealer.saved_changes.except("updated_at", "created_at", "password_digest", "status")

          profile_after = @dealer.dealer_profile&.attributes || {}
          profile_diff = profile_before.keys.each_with_object({}) do |key, diff|
            next if %w[updated_at created_at id dealer_id].include?(key)
            if profile_before[key] != profile_after[key]
              diff["profile_#{key}"] = { from: profile_before[key], to: profile_after[key] }
            end
          end

          location_after = @dealer.dealer_location&.attributes || {}
          location_diff = location_before.keys.each_with_object({}) do |key, diff|
            next if %w[updated_at created_at id dealer_id].include?(key)
            if location_before[key] != location_after[key]
              diff["location_#{key}"] = { from: location_before[key], to: location_after[key] }
            end
          end

          dealer_diff = dealer_changes.transform_values { |v| { from: v[0], to: v[1] } }
          combined_diff = dealer_diff.merge(profile_diff).merge(location_diff)

          bank_keys = %w[
            profile_bank_name profile_bank_account_number profile_ifsc_code profile_account_holder_name
            profile_bank_verification_status profile_bank_verification_reference profile_bank_verified_at
            profile_verified_bank_name profile_verified_name_at_bank profile_last_bank_verification_error profile_bank_verification_payload
          ]
          non_bank_diff = combined_diff.reject { |k, _| bank_keys.include?(k.to_s) }

          if non_bank_diff.present?
            @dealer.update_columns(status: "pending")
            notify_admins_about_dealer_reverification(@dealer, non_bank_diff)

            render json: serialize_resource(@dealer, DealerSerializer, base_url: request.base_url).merge(
              message: "Profile updated successfully. Your account is under re-verification by Admin (Status: Pending)."
            ), status: :ok
            return
          end
        end

        notify_admins_entity_updated(@dealer)
        render json: serialize_resource(@dealer, DealerSerializer, base_url: request.base_url).merge(message: "Dealer updated successfully"), status: :ok
      else
        render json: {
          error: @dealer.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def verify_bank_account
      service = DealerBankVerificationService.new(dealer: @dealer)
      result = service.verify!(
        account_number: params[:bank_account_number],
        confirm_account_number: params[:confirm_bank_account_number],
        account_holder_name: params[:account_holder_name],
        ifsc_code: params[:ifsc_code]
      )

      if result.status == "pending"
        render json: {
          data: {
            verification_reference: result.verification_reference,
            cashfree_reference_id: result.cashfree_reference_id,
            bank_name: result.bank_name,
            name_at_bank: result.name_at_bank,
            account_holder_name: result.account_holder_name,
            ifsc_code: result.ifsc_code,
            masked_account_number: "XXXXXX#{result.account_number.to_s.last(4)}",
            status: "pending"
          },
          message: "Bank account verification is in progress"
        }, status: :accepted

        return
      end

      render json: {
        data: {
          verification_reference: result.verification_reference,
          cashfree_reference_id: result.cashfree_reference_id,
          bank_name: result.bank_name,
          name_at_bank: result.name_at_bank,
          account_holder_name: result.account_holder_name,
          ifsc_code: result.ifsc_code,
          masked_account_number: "XXXXXX#{result.account_number.to_s.last(4)}",
          status: "verified"
        },
        message: "Bank account verified successfully"
      }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
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
      dealer = find_signup_dealer || @dealer
      unless dealer
        return render json: { error: "Dealer record not found." }, status: :not_found
      end

      if dealer.signup_token.blank? || dealer.otp_pin.blank?
        return render json: { error: "This verification link has already been used or verified. Please log in.", verified_or_expired: true }, status: :unprocessable_entity
      end

      unless dealer.otp_valid?(params[:otp].to_s)
        return render json: { error: "Invalid or expired 6-digit OTP (10 min limit)." }, status: :unauthorized
      end

      temp_password = SecureRandom.hex(6)
      dealer.update!(password: temp_password, password_confirmation: temp_password)
      dealer.clear_otp!

      DealerMailer.welcome_email(dealer, temp_password).deliver_later if dealer.email.present?
      notify_admins_about_dealer_approval(dealer)

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
          :id, :business_name, :gst_number, :pan_number, :aadhar_number,
          :bank_name, :bank_account_number, :ifsc_code, :account_holder_name, :business_address,
          :business_contact_number, :business_email, :associated_brands,
          :is_verified, :bank_verification_reference, :pan_card, :gst_certificate, :cancel_cheque, 
          { business_type: [], work_category: [], store_image: [], aadhar_card: [], brand_invoices: [] }
        ],
        dealer_location_attributes: [:id, :latitude, :longitude, :service_radius_km, :is_active]
      )
    end

    def normalize_verified_bank_payload!
      attrs = params.dig(:dealer, :dealer_profile_attributes)
      return if attrs.blank?
      return unless current_user_type == "Dealer"

      profile = @dealer.dealer_profile
      incoming_account = attrs[:bank_account_number].to_s.gsub(/\s+/, "")
      incoming_ifsc = attrs[:ifsc_code].to_s.strip.upcase
      incoming_holder = attrs[:account_holder_name].to_s.squish

      # Return early if bank account is not being changed or updated
      return if incoming_account.blank?

      existing_matches =
        profile.present? &&
        profile.bank_account_number.to_s == incoming_account &&
        (incoming_ifsc.blank? || profile.ifsc_code.to_s.upcase == incoming_ifsc) &&
        (incoming_holder.blank? || profile.account_holder_name.to_s.casecmp?(incoming_holder))

      return if existing_matches

      verification_reference = attrs[:bank_verification_reference].presence
      raise StandardError, "Please verify bank account before saving these details" if verification_reference.blank?

      verification_payload = DealerBankVerificationService.new(dealer: @dealer).consume_verified_payload!(
        verification_reference: verification_reference,
        account_number: incoming_account,
        ifsc_code: incoming_ifsc,
        account_holder_name: incoming_holder
      )

      attrs[:bank_name] = verification_payload[:bank_name]
      attrs[:account_holder_name] = verification_payload[:account_holder_name]
      target_profile = profile || @dealer.build_dealer_profile
      DealerBankVerificationService.new(dealer: @dealer).persist_verified_profile!(
        profile: target_profile,
        verification_payload: verification_payload
      )
    end

    def find_signup_dealer
      token_or_id = params[:token].presence || params[:id].presence
      dealer = Dealer.find_by(signup_token: token_or_id) if token_or_id.present?
      dealer ||= Dealer.find_by(id: token_or_id) if token_or_id.present?
      dealer
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
      details = dealer.attributes.except("id", "created_at", "updated_at", "password_digest")
      admin_emails.each do |email|
        AdminNotificationMailer.dealer_action(email, dealer.full_name, "registered", dealer, details, "New dealer registered").deliver_later
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

    def notify_admins_about_dealer_action(dealer, action, details = nil, changes = {})
      admin_emails = get_admin_emails
      admin_emails.each do |email|
        AdminNotificationMailer.dealer_action(email, dealer.full_name, action, current_admin || dealer, changes, details).deliver_later
      end
    end

    def notify_admins_entity_updated(dealer)
      changes = dealer.saved_changes.except("updated_at", "created_at", "password_digest").transform_values { |v| { from: v[0], to: v[1] } }
      get_admin_emails.each do |email|
        AdminNotificationMailer.entity_updated(email, "Dealer", dealer.full_name, current_admin, changes).deliver_later
      end
    end

    def notify_admins_about_dealer_reverification(dealer, changes_diff)
      AdminUser.where(status: "active").find_each do |admin|
        NotificationService.deliver(
          recipient: admin,
          kind: "dealer_reverification_requested",
          title: "Dealer Re-Verification Required",
          message: "Dealer #{dealer.full_name} (#{dealer.dealer_profile&.business_name || 'N/A'}) updated profile details. Account status set to Pending.",
          notifiable: dealer,
          actor: dealer
        )
      end

      get_admin_emails.each do |email|
        AdminNotificationMailer.dealer_reverification_requested(email, dealer, changes_diff).deliver_later
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
        mf_year: post.mf_year,
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
