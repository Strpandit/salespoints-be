class DeliveryConfirmationService
  BASE_REQUIRED_DECLARATIONS = %w[
    delivered_without_fraud
    packaging_checked
    customer_consent_open_box
    terms_accepted
  ].freeze

  def initialize(deliverable:, actor: nil)
    @deliverable = deliverable
    @actor = actor
  end

  def create_or_refresh!
    confirmation = @deliverable.delivery_confirmation || build_confirmation(context: "original")
    confirmation.status = "pending_form" unless confirmation.completed?
    confirmation.seller_phone ||= phone_for(seller)
    confirmation.buyer_phone ||= phone_for(buyer)
    confirmation.save!

    send_form_link(confirmation)
    create_pending_notification(confirmation)
    confirmation
  end

  def create_replacement!(return_request:)
    existing = @deliverable.replacement_delivery_confirmation

    if existing&.completed?
      send_form_link(existing)
      return existing
    end

    existing&.destroy!

    confirmation = build_confirmation(context: "replacement")
    confirmation.return_request_id = return_request.id
    confirmation.save!

    send_form_link(confirmation)
    create_pending_notification(confirmation)
    confirmation
  end

  def submit_form!(confirmation:, declarations:, notes:, serial_numbers:, files:)
    @confirmation = confirmation
    ensure_required_declarations!(declarations)
    ensure_required_files!(files)
    ensure_serial_numbers_match!(serial_numbers)

    confirmation.declarations = normalized_declarations(declarations)
    confirmation.notes = notes.to_s.strip.presence
    confirmation.serial_numbers = Array(serial_numbers).reject(&:blank?)
    attach_files!(confirmation, files)
    confirmation.submitted_at = Time.current
    confirmation.status = "pending_otp"
    confirmation.save!

    send_otps!(confirmation)
    confirmation
  end

  def send_otps!(confirmation)
    confirmation.update!(
      buyer_otp: generated_otp,
      seller_otp: nil,
      seller_otp_sent_at: nil,
      buyer_otp_sent_at: Time.current
    )

    send_otp_message(phone: confirmation.buyer_phone, otp: confirmation.buyer_otp)
    send_otp_email(confirmation)
  end

  def send_otp_email(confirmation)
    DeliveryConfirmationMailer.send_delivery_otp(confirmation.id, confirmation.buyer_otp).deliver_later
  rescue StandardError => e
    Rails.logger.error("[DeliveryConfirmationMailer] Failed to send OTP email: #{e.message}")
  end

  def verify_otps!(confirmation:, buyer_otp:)
    raise StandardError, "Delivery proof form is not submitted yet" unless confirmation.pending_otp? || confirmation.completed?
    raise StandardError, "Invalid buyer OTP" unless confirmation.buyer_otp_valid?(buyer_otp)

    ActiveRecord::Base.transaction do
      confirmation.update!(
        buyer_otp_verified_at: confirmation.buyer_otp_verified_at || Time.current,
        seller_otp: nil,
        buyer_otp: nil,
        status: "completed",
        completed_at: confirmation.completed_at || Time.current
      )

      mark_delivered!(confirmation: confirmation)
      mark_payment_paid_if_required!
      create_completed_notifications(confirmation)
      send_delivery_emails
    end

    confirmation.reload
  end

  private

  def build_confirmation(context: "original")
    DeliveryConfirmation.new(
      deliverable: @deliverable,
      seller_dealer: seller,
      buyer: buyer,
      seller_phone: phone_for(seller),
      buyer_phone: phone_for(buyer),
      context: context
    )
  end

  def ensure_required_declarations!(declarations)
    normalized = normalized_declarations(declarations)
    required = BASE_REQUIRED_DECLARATIONS.dup
    required << "payment_collected" if cod_payment_pending?
    missing = required.reject { |key| normalized[key] == true }
    raise StandardError, "Please accept all required declarations" if missing.any?
  end

  def normalized_declarations(declarations)
    source = declarations.respond_to?(:to_unsafe_h) ? declarations.to_unsafe_h : declarations.to_h
    source.to_h.transform_keys(&:to_s).transform_values { |value| ActiveModel::Type::Boolean.new.cast(value) }
  end

  def ensure_required_files!(files)
    raise StandardError, "Product with customer image is required" if files[:product_with_customer_image].blank?
    raise StandardError, "Product packaging image is required" if files[:product_packaging_image].blank?
    raise StandardError, "At least one open box product image is required" if Array(files[:product_open_box_images]).reject(&:blank?).blank?
  end

  def ensure_serial_numbers_match!(serial_numbers)
    provided_serials = Array(serial_numbers).reject(&:blank?)

    if @confirmation&.context == "replacement" && @confirmation&.return_request_id.present?
      return_request = ReturnRequest.find_by(id: @confirmation.return_request_id)
      if return_request && return_request.partial_replacement?
        expected_qty = return_request.defective_quantity.to_i
        if provided_serials.length != expected_qty
          raise StandardError, "For partial replacement, please provide exactly #{expected_qty} replacement serial numbers (you provided #{provided_serials.length})"
        end
        return
      end
    end

    expected_qty = case @deliverable
                   when Order then @deliverable.order_items.sum(:quantity)
                   when B2bOrder then @deliverable.b2b_order_items.sum(:quantity)
                   else 0
                   end

    if provided_serials.length != expected_qty
      raise StandardError, "Please provide exactly #{expected_qty} serial numbers (you provided #{provided_serials.length})"
    end
  end

  def attach_files!(confirmation, files)
    confirmation.product_with_customer_image.purge if confirmation.product_with_customer_image.attached?
    confirmation.product_packaging_image.purge if confirmation.product_packaging_image.attached?
    confirmation.product_open_box_images.purge if confirmation.product_open_box_images.attached?

    confirmation.product_with_customer_image.attach(files[:product_with_customer_image])
    confirmation.product_packaging_image.attach(files[:product_packaging_image])
    Array(files[:product_open_box_images]).reject(&:blank?).each do |file|
      confirmation.product_open_box_images.attach(file)
    end
  end

  def generated_otp
    rand(100000..999999).to_s
  end

  def mark_delivered!(confirmation: nil)
    effective_actor = @actor || @deliverable.try(:seller_dealer) || @deliverable.try(:buyer)
    is_replacement = (confirmation&.context == "replacement") || @deliverable.status.to_s == "replacement_shipped"

    if is_replacement
      request = @deliverable.return_requests.where(request_type: "replacement").order(created_at: :desc).first
      if request
        if confirmation&.serial_numbers.present?
          request.update!(replacement_serial_numbers: confirmation.serial_numbers)
        end

        if request.partial_replacement? && request.defective_serial_numbers.present? && confirmation&.serial_numbers.present?
          original_confirmation = @deliverable.delivery_confirmation
          if original_confirmation&.serial_numbers.present?
            updated_serials = original_confirmation.serial_numbers.dup
            defective = Array(request.defective_serial_numbers)
            new_serials = Array(confirmation.serial_numbers)

            defective.each_with_index do |def_sn, idx|
              replacement_sn = new_serials[idx] || def_sn
              pos = updated_serials.index(def_sn)
              if pos
                updated_serials[pos] = replacement_sn
              else
                updated_serials << replacement_sn
              end
            end
            original_confirmation.update!(serial_numbers: updated_serials)
          end
        end

        begin
          ReturnRequestTransitionService.new(
            return_request: request,
            actor: effective_actor,
            resolution_notes: "Replacement delivered after OTP verification."
          ).transition!(next_status: "received")
        rescue StandardError => e
          Rails.logger.warn("ReturnRequestTransitionService transition error: #{e.message}")
        end

        request.reload rescue nil
        request.update!(
          status: "received",
          completed_at: request.completed_at || Time.current,
          resolution_notes: "Replacement delivered after OTP verification."
        ) rescue nil

        ReplacementRequestNotificationService.request_completed!(request, actor: effective_actor) rescue nil
      end

      @deliverable.update!(status: "replacement_delivered", status_note: "Replacement delivered after OTP verification.")
      dispatch_delivery_email!
      return
    end

    case @deliverable
    when Order
      OrderLifecycleService.new(
        order: @deliverable,
        actor: effective_actor,
        status_note: "Delivery completed after OTP verification."
      ).transition!(next_status: "delivered")
    when B2bOrder
      @deliverable.mark_delivered!(note: "Delivery completed after OTP verification.")
    else
      raise StandardError, "Unsupported deliverable type"
    end
  end

  def mark_payment_paid_if_required!
    return unless cod_payment_pending?

    case @deliverable
    when Order
      @deliverable.mark_payment_paid!

    when B2bOrder
      @deliverable.update!(
        payment_status: "paid",
        payment_confirmed_at: @deliverable.payment_confirmed_at || Time.current
      )

      @deliverable.buyer_payment_attempt&.mark_paid!(
        reference: nil,
        gateway_payload: {}
      )
    end
  end

  def phone_for(target)
    return nil if target.blank?

    raw_phone = target.try(:phone)
    if raw_phone.blank? && target.respond_to?(:dealer_profile)
      raw_phone = target.dealer_profile&.business_contact_number
    end

    if raw_phone.blank? && @deliverable.respond_to?(:shipping_address) && target == buyer
      addr = @deliverable.shipping_address
      raw_phone = addr&.dig("phone") || addr&.dig(:phone) if addr.is_a?(Hash)
    end

    return nil if raw_phone.blank?

    cc = target.try(:country_code).presence || "+91"
    cc = "+#{cc.delete_prefix('+')}" unless cc.start_with?("+")
    raw_digits = raw_phone.to_s.gsub(/\D/, "").last(10)
    "#{cc}#{raw_digits}".delete_prefix("+")
  end

  def seller
    @deliverable.try(:seller_dealer)
  end

  def buyer
    case @deliverable
    when Order then @deliverable.buyer
    when B2bOrder then @deliverable.buyer_dealer
    else nil
    end
  end

  def cod_payment_pending?
    @deliverable.try(:payment_method).to_s.downcase == "cod" &&
      @deliverable.try(:payment_status).to_s.downcase != "paid"
  end

  def send_form_link(confirmation)
    token = confirmation.token
    link = "#{frontend_base_url}/delivery-confirmation/#{token}"
    order_ref = @deliverable.try(:reference_number) || @deliverable.try(:order_number)
    buyer_title = confirmation.buyer_name || "Customer"

    # Send WhatsApp delivery form link
    whatsapp = MetaWhatsappCloudService.new
    if whatsapp.configured? && confirmation.seller_phone.present?
      begin
        whatsapp.send_delivery_form_link(
          to: confirmation.seller_phone,
          order_reference: order_ref.to_s,
          buyer_name: buyer_title.to_s,
          form_url: link.to_s
        )
      rescue StandardError => e
        Rails.logger.warn("[MetaWhatsapp] Failed to send delivery_form_link template: #{e.message}. Falling back to text message.")
        begin
          message = "SalesPoints: Complete delivery proof for #{order_ref} at #{link}"
          whatsapp.send_text_message(to: confirmation.seller_phone, body: message)
        rescue StandardError => err
          Rails.logger.error("[MetaWhatsapp] Failed to send delivery form text message: #{err.message}")
        end
      end
    end

    message = "SalesPoints: Complete delivery proof for #{order_ref} at #{link}"
    send_sms_notification(confirmation.seller_phone, message)
  end

  def send_otp_message(phone:, otp:)
    return if phone.blank?

    whatsapp = MetaWhatsappCloudService.new
    if whatsapp.configured?
      begin
        whatsapp.send_delivery_otp(to: phone, otp: otp)
      rescue StandardError => e
        Rails.logger.warn("[MetaWhatsapp] Failed to send delivery_code template: #{e.message}. Falling back to text message.")
        begin
          message = "SalesPoints: Your delivery verification OTP is #{otp}. Share this with the delivery agent to confirm delivery."
          whatsapp.send_text_message(to: phone, body: message)
        rescue StandardError => err
          Rails.logger.error("[MetaWhatsapp] Failed to send delivery OTP text message: #{err.message}")
        end
      end
    end

    message = "SalesPoints: Your delivery verification OTP is #{otp}. Share this with the delivery agent to confirm delivery."
    send_sms_notification(phone, message)
  end

  def send_sms_notification(phone, message)
    return if phone.blank?
    Rails.logger.info("[SMS NOTIFICATION] To: #{phone} | #{message}")
  end

  def create_pending_notification(confirmation)
    return unless seller.is_a?(Dealer)

    NotificationService.deliver(
      recipient: seller,
      kind: "delivery_confirmation",
      title: "Delivery Proof Required",
      message: "Please complete delivery proof form for #{@deliverable.try(:reference_number) || @deliverable.try(:order_number)}",
      notifiable: @deliverable,
      actor: @actor,
      payload: {
        confirmation_id: confirmation.id,
        token: confirmation.token,
        deliverable_type: @deliverable.class.name,
        deliverable_id: @deliverable.id
      }
    )
  end

  def create_completed_notifications(confirmation)
    if seller.is_a?(Dealer)
      NotificationService.deliver(
        recipient: seller,
        kind: "delivery_completed",
        title: "Delivery Verified",
        message: "Order #{@deliverable.try(:reference_number) || @deliverable.try(:order_number)} delivery has been confirmed by buyer OTP.",
        notifiable: @deliverable,
        actor: @actor,
        payload: { confirmation_id: confirmation.id }
      )
    end
  end

  def send_delivery_emails
    Rails.logger.info("[DELIVERY EMAIL] Delivery confirmation completed for #{@deliverable.class.name} ##{@deliverable.id}")
  end

  def dispatch_delivery_email!
    if @deliverable.is_a?(Order)
      EmailDispatcherService.retail_order_delivered(@deliverable)
    elsif @deliverable.is_a?(B2bOrder)
      EmailDispatcherService.b2b_order_delivered(@deliverable)
    end
  end

  def frontend_base_url
    ENV.fetch("FRONTEND_URL", "https://salespoints.in")
  end
end
