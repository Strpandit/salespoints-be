module Api
  class DealerSessionsController < ApplicationController
    skip_before_action :authenticate_request!, only: [:login, :forgot_password, :otp_confirmation, :reset_password]

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
      DealerAuthMailer.forgot_password_otp(dealer).deliver_later if dealer.email.present?
      render json: { message: "OTP sent successfully", id: dealer.id }, status: :ok
    end

    def otp_confirmation
      dealer = Dealer.active.find(params[:id])
      return unauthorized("Invalid OTP") unless dealer.otp_pin.to_s == params[:otp].to_s

      render json: { message: "OTP verified successfully" }, status: :ok
    end

    def reset_password
      dealer = Dealer.active.find(params[:id])
      if dealer.update(password: params[:password], password_confirmation: params[:password_confirmation])
        dealer.update(otp_pin: nil, otp_sent_at: nil)
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
  end
end
