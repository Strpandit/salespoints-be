module Api
  class DealerSessionsController < ApplicationController
    skip_before_action :authenticate_request!, only: [:login, :forgot_password, :otp_confirmation, :reset_password]
    RESET_FLOW_TTL = 10.minutes

    def login
      dealer = Dealer.active.find_by(email: params[:email]&.downcase) || Dealer.find_by(phone: params[:phone]&.gsub(/\D/, ''))

      return unauthorized("Invalid credentials"), status: :unauthorized unless dealer&.authenticate(params[:password]) && dealer.active?

      token = JsonWebToken.encode(user_id: dealer.id, user_type: "Dealer")

      render json: {
        token: token,
        dealer: serialize_data(dealer, DealerSerializer),
        message: "Logged in successfully"
      }, status: :ok
    end

    def change_password
      dealer = current_dealer

      unless dealer.authenticate(params[:current_password])
        return render json:{error:"Incorrect password"}, status: :unauthorized
      end

      if dealer.update(
        password: params[:new_password],
        password_confirmation: params[:confirm_password]
      )
        render json:{message:"Password changed"}, status: :ok
      else
        render json:{error: dealer.errors.full_messages}, status: :unprocessable_entity
      end
    end

    def forgot_password
      dealer = Dealer.active.find_by(email: params[:email]&.downcase) || Dealer.active.find_by(phone: params[:phone]&.gsub(/\D/, ''))
      return unauthorized("Dealer not found") unless dealer
      return render json: { error: "Dealer email not available" }, status: :unprocessable_entity if dealer.email.blank?

      dealer.update!(otp_pin: rand(1000..9999), otp_sent_at: Time.current)
      Rails.cache.delete(reset_flow_cache_key(dealer.id))
      DealerAuthMailer.forgot_password_otp(dealer).deliver_later if dealer.email.present?
      render json: { message: "OTP sent successfully", id: dealer.id }, status: :ok
    end

    def otp_confirmation
      dealer = Dealer.active.find(params[:id])
      return unauthorized("Invalid OTP") unless dealer.otp_valid?(params[:otp].to_s)

      reset_token = SecureRandom.hex(24)
      Rails.cache.write(reset_flow_cache_key(dealer.id), reset_token, expires_in: RESET_FLOW_TTL)

      render json: { message: "OTP verified successfully", reset_token: reset_token }, status: :ok
    end

    def reset_password
      dealer = Dealer.active.find(params[:id])
      reset_token = params[:reset_token].to_s
      cached_token = Rails.cache.read(reset_flow_cache_key(dealer.id)).to_s
      return unauthorized("Reset session expired. Verify OTP again.") if reset_token.blank? || cached_token.blank? || cached_token != reset_token

      if dealer.update(password: params[:password], password_confirmation: params[:password_confirmation])
        dealer.update(otp_pin: nil, otp_sent_at: nil)
        Rails.cache.delete(reset_flow_cache_key(dealer.id))
        DealerAuthMailer.password_reset_confirmation(dealer).deliver_later if dealer.email.present?
        render json: { message: "Password reset successfully" }, status: :ok
      else
        render json: { error: dealer.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def unauthorized(msg)
      render json: { error: msg }, status: :unauthorized and return
    end

    def reset_flow_cache_key(dealer_id)
      "dealer_password_reset_verified:#{dealer_id}"
    end
  end
end
