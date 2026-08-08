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
    confirmation = @deliverable.delivery_confirmation || build_confirmation
    confirmation.status = "pending_form" unless confirmation.completed?
    confirmation.seller_phone ||= phone_for(seller)
    confirmation.buyer_phone ||= phone_for(buyer)
    confirmation.save!

    send_form_link(confirmation)
    create_pending_notification(confirmation)
    confirmation
  end

  def submit_form!(confirmation:, declarations:, notes:, serial_numbers:, files:)
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

      mark_delivered!
      mark_payment_paid_if_required!
      create_completed_notifications(confirmation)
      send_delivery_emails
    end

    confirmation.reload
  end

  private

  def build_confirmation
    DeliveryConfirmation.new(
      deliverable: @deliverable,
      seller_dealer: seller,
      buyer: buyer,
      seller_phone: phone_for(seller),
      buyer_phone: phone_for(buyer)
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
    expected_qty = case @deliverable
                   when Order then @deliverable.order_items.sum(:quantity)
                   when B2bOrder then @deliverable.b2b_order_items.sum(:quantity)
                   else 0
                   end
    
    provided_serials = Array(serial_numbers).reject(&:blank?)
    
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

  def mark_delivered!
    case @deliverable
    when Order
      OrderLifecycleService.new(
        order: @deliverable,
        actor: @actor,
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

  def cod_payment_pending?
    @deliverable.payment_method.to_s.downcase == "cod" &&
      @deliverable.payment_status.to_s.downcase == "pending"
  end

  def create_pending_notification(confirmation)
    return if seller.blank?

    NotificationService.deliver(
      recipient: seller,
      actor: @actor,
      notifiable: @deliverable,
      kind: "delivery_confirmation_pending",
      title: "Delivery verification required",
      message: "Please complete the delivery verification form for #{deliverable_reference}.",
      payload: {
        delivery_confirmation_token: confirmation.token,
        reference: deliverable_reference
      },
      delivery_channels: { push: true, whatsapp: true, in_app: true }
    )
  end

  def create_completed_notifications(confirmation)
    [buyer, seller].compact.each do |recipient|
      NotificationService.deliver(
        recipient: recipient,
        actor: @actor || seller,
        notifiable: @deliverable,
        kind: "delivery_completed",
        title: "Delivery completed",
        message: "#{deliverable_reference} has been marked as delivered after OTP verification.",
        payload: {
          delivery_confirmation_token: confirmation.token,
          reference: deliverable_reference,
          completed_at: confirmation.completed_at,
          payment_status: @deliverable.payment_status
        },
        delivery_channels: { push: true, email: true, in_app: true }
      )
    end
  end

  def send_form_link(confirmation)
    return if confirmation.seller_phone.blank?

    MetaWhatsappCloudService.new.send_delivery_form_link(
      to: confirmation.seller_phone,
      order_reference: deliverable_reference,
      buyer_name: confirmation.buyer_name,
      form_url: delivery_form_url(confirmation)
    )
  end

  def send_otp_message(phone:, otp:)
    return if phone.blank?

    MetaWhatsappCloudService.new.send_delivery_otp(
      to: phone,
      otp: otp
    )
  end

  def send_delivery_emails
    case @deliverable
    when Order
      # Email already sent by OrderLifecycleService during mark_delivered!
    when B2bOrder
      EmailDispatcherService.b2b_order_delivered(@deliverable)
    end
  end

  def deliverable_reference
    case @deliverable
    when Order
      @deliverable.order_number
    when B2bOrder
      @deliverable.reference_number
    end
  end

  def delivery_form_url(confirmation)
    base = ENV["FRONTEND_URL"].to_s.presence || "http://localhost:5173"
    "#{base.delete_suffix('/')}/delivery-confirmation/#{confirmation.token}"
  end

  def seller
    @seller ||= case @deliverable
                when Order then @deliverable.seller_dealer
                when B2bOrder then @deliverable.seller_dealer
                end
  end

  def buyer
    @buyer ||= case @deliverable
               when Order then @deliverable.buyer
               when B2bOrder then @deliverable.buyer_dealer
               end
  end

  def buyer_label
    @deliverable.is_a?(B2bOrder) ? "Buyer" : "Customer"
  end

  def phone_for(record)
    return nil if record.blank?

    phone = record.phone.presence

    if phone.blank? && @deliverable.is_a?(Order) && record == buyer
      phone = @deliverable.shipping_address&.dig("phone")
    end

    return nil if phone.blank?

    cc = record.try(:country_code).presence || @deliverable.shipping_address&.dig("country_code").presence || "+91"
    "#{cc}#{phone}".gsub(/\s+/, "")
  end
end
