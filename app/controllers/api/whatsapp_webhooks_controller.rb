module Api
  class WhatsappWebhooksController < ApplicationController
    skip_before_action :authenticate_request!

    def verify
      verify_token = ENV["META_WHATSAPP_VERIFY_TOKEN"].to_s

      if params["hub.mode"] == "subscribe" && params["hub.verify_token"].to_s == verify_token
        render plain: params["hub.challenge"].to_s, status: :ok
      else
        render plain: "Verification failed", status: :forbidden
      end
    end

    def receive
      MetaWhatsappWebhookService.new(headers: request.headers, raw_body: request.raw_post).call
      head :ok
    rescue StandardError => e
      Rails.logger.error("Meta WhatsApp webhook error: #{e.message}")
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
