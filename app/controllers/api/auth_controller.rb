module Api
  class AuthController < ApplicationController
    skip_before_action :authenticate_request!
    # Login via email/phone + otp
    def send_otp
      identifier = params[:identifier].to_s.strip
      signup = ActiveModel::Type::Boolean.new.cast(params[:signup])

      is_email = identifier.include?('@')
      normalized_phone = identifier.gsub(/\D/, '')

      account = is_email ?
              Account.find_by(email: identifier.downcase) :
              Account.find_by(phone: normalized_phone)

      if !signup
        return render json: {
          error: "Account not found. Please sign up."
        }, status: :not_found unless account
      end

      if signup
        if account.present?
          return render json: {
            error: is_email ?
              "Email already registered. Please login." :
              "Phone number already registered. Please login."
          }, status: :unprocessable_entity
        end

        account = Account.create!(
          email: is_email ? identifier.downcase : nil,
          phone: is_email ? nil : normalized_phone,
          country_code: ENV.fetch('DEFAULT_COUNTRY_CODE', '+91'),
          status: 'pending'
        )

        # Send signup email notification
        AccountMailer.signup_email(account).deliver_later if account.email.present?
      end
      OtpService.send_otp(account)
      render json: { message: "OTP sent successfully", flow: signup ? 'signup' : 'login' }
    end

    def verify_otp
      identifier = params[:identifier].to_s.strip
      otp = params[:otp].to_s
      account = identifier.include?('@') ?
                  Account.find_by(email: identifier.downcase) :
                  Account.find_by(phone: identifier.gsub(/\D/, ''))

      return render json: { error: 'Invalid OTP' }, status: :unauthorized unless account&.otp_valid?(otp)

      account.clear_otp!
      
      # Send login notification (only for existing accounts, not signup)
      is_signup = account.status == 'pending'
      unless is_signup
        AccountMailer.login_notification(account).deliver_later if account.email.present?
      end
      
      # Mark account as active after successful login
      account.update(status: 'active') if is_signup
      
      token = JsonWebToken.encode(user_id: account.id, user_type: 'Account')

      render json: {
        message: is_signup ? 'Signup successful' : 'Login successful',
        token: token,
        account: AccountSerializer.new(account)
      }
    end

    def google_login
      result = GoogleTokenVerifier.verify(params[:id_token])

      return render json: { error: 'Invalid Google token' }, status: :unauthorized unless result

      account = Account.find_or_initialize_by(email: result[:email])

      if account.new_record?
        account.assign_attributes(
          provider: 'google',
          provider_uid: result[:uid],
          google_signup: true,
          status: 'active',
          password: SecureRandom.urlsafe_base64(12),
          password_confirmation: SecureRandom.urlsafe_base64(12)
        )
        account.save!
      end

      token = JsonWebToken.encode(user_id: account.id, user_type: 'Account')

      render json: {
        token: token,
        account: AccountSerializer.new(account)
      }
    end
  end
end
