class DeliveryConfirmationMailer < ApplicationMailer
  default from: "SalesPoints <salespointecom@gmail.com>"

  def send_delivery_otp(confirmation_id, otp)
    @confirmation = DeliveryConfirmation.find_by(id: confirmation_id)
    return unless @confirmation.present?

    @otp = otp
    @deliverable = @confirmation.deliverable
    @order_ref = @deliverable.try(:order_number) || @deliverable.try(:reference_number) || "##{@deliverable.id}"
    @buyer_name = @confirmation.buyer_name || "Customer"

    recipient_email = if @deliverable.is_a?(Order)
                        @deliverable.buyer&.try(:email)
                      elsif @deliverable.is_a?(B2bOrder)
                        @deliverable.buyer_dealer&.try(:email)
                      end

    return if recipient_email.blank?

    mail(to: recipient_email, subject: "Your Delivery Verification OTP - Order #{@order_ref}")
  end
end
