module Api
  class DeliveryConfirmationsController < ApplicationController
    skip_before_action :authenticate_request!
    before_action :set_confirmation

    def show
      render json: serialize_resource(@confirmation, DeliveryConfirmationSerializer, include: []).merge(
        deliverable: serialized_deliverable,
        message: "Delivery confirmation fetched successfully"
      ), status: :ok
    end

    def submit
      service.submit_form!(
        confirmation: @confirmation,
        declarations: params[:declarations] || {},
        notes: params[:notes],
        files: {
          product_with_customer_image: params[:product_with_customer_image],
          product_packaging_image: params[:product_packaging_image],
          product_open_box_images: params[:product_open_box_images]
        }
      )

      render json: serialize_resource(@confirmation.reload, DeliveryConfirmationSerializer).merge(
        deliverable: serialized_deliverable,
        message: "Delivery proof submitted. OTP sent to buyer."
      ), status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def resend_otps
      service.send_otps!(@confirmation)

      render json: serialize_resource(@confirmation.reload, DeliveryConfirmationSerializer).merge(
        message: "OTPs sent successfully"
      ), status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def verify_otps
      confirmation = service.verify_otps!(
        confirmation: @confirmation,
        buyer_otp: params[:buyer_otp]
      )

      render json: serialize_resource(confirmation, DeliveryConfirmationSerializer).merge(
        deliverable: serialized_deliverable,
        message: "Delivery verified successfully"
      ), status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def set_confirmation
      @confirmation = DeliveryConfirmation.includes(:seller_dealer, :buyer, :deliverable).find_by(token: params[:token] || params[:id])
      return if @confirmation.present?

      render json: { error: "Delivery confirmation not found" }, status: :not_found
    end

    def service
      @service ||= DeliveryConfirmationService.new(deliverable: @confirmation.deliverable)
    end

    def serialized_deliverable
      case @confirmation.deliverable
      when Order
        OrderSerializer.render(@confirmation.deliverable, include: [:delivery_confirmation])
      when B2bOrder
        B2bOrderSerializer.render(@confirmation.deliverable, include: [:delivery_confirmation])
      end
    end
  end
end
