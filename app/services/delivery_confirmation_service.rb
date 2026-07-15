class DeliveryConfirmationService
  REQUIRED_DECLARATIONS = %w[
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

  def submit_form!(confirmation:, declarations:, notes:, files:)
    ensure_required_declarations!(declarations)
    ensure_required_files!(files)

    confirmation.declarations = normalized_declarations(declarations)
    confirmation.notes = notes.to_s.strip.presence
    attach_files!(confirmation, files)
    confirmation.submitted_at = Time.current
    confirmation.status = "pending_otp"
    confirmation.save!

    send_otps!(confirmation)
    confirmation
  end

  def send_otps!(confirmation)
    confirmation.update!(
      seller_otp: generated_otp,
      buyer_otp: generated_otp,
      seller_otp_sent_at: Time.current,
      buyer_otp_sent_at: Time.current
    )

    send_otp_message(phone: confirmation.seller_phone, otp: confirmation.seller_otp)
    send_otp_message(phone: confirmation.buyer_phone, otp: confirmation.buyer_otp)
  end

  def verify_otps!(confirmation:, seller_otp:, buyer_otp:)
    raise StandardError, "Delivery proof form is not submitted yet" unless confirmation.pending_otp? || confirmation.completed?
    raise StandardError, "Invalid seller OTP" unless confirmation.seller_otp_valid?(seller_otp)
    raise StandardError, "Invalid buyer OTP" unless confirmation.buyer_otp_valid?(buyer_otp)

    ActiveRecord::Base.transaction do
      confirmation.update!(
        seller_otp_verified_at: confirmation.seller_otp_verified_at || Time.current,
        buyer_otp_verified_at: confirmation.buyer_otp_verified_at || Time.current,
        seller_otp: nil,
        buyer_otp: nil,
        status: "completed",
        completed_at: confirmation.completed_at || Time.current
      )

      mark_delivered!
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
    missing = REQUIRED_DECLARATIONS.reject { |key| normalized[key] == true }
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
          completed_at: confirmation.completed_at
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
      OrderMailer.delivery_invoice(@deliverable.id, "buyer").deliver_later if @deliverable.buyer&.email.present?
      OrderMailer.delivery_invoice(@deliverable.id, "seller").deliver_later if @deliverable.seller_dealer&.email.present?
    when B2bOrder
      B2bOrderMailer.delivery_invoice(@deliverable.id, "buyer").deliver_later if @deliverable.buyer_dealer&.email.present?
      B2bOrderMailer.delivery_invoice(@deliverable.id, "seller").deliver_later if @deliverable.seller_dealer&.email.present?
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
    return nil if record.blank? || record.phone.blank?

    cc = record.try(:country_code).presence || "+91"
    "#{cc}#{record.phone}".gsub(/\s+/, "")
  end
end
