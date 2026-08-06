module Api
  class AuthController < ApplicationController
    skip_before_action :authenticate_request!
    # Login/Signup via email or phone + 6-digit WhatsApp OTP (Account only)
    def send_otp
      identifier = params[:identifier].to_s.strip
      signup = ActiveModel::Type::Boolean.new.cast(params[:signup])

      if identifier.blank?
        return render json: { error: "Email or Phone number is required" }, status: :unprocessable_entity
      end

      is_email = identifier.include?('@')
      normalized_phone = is_email ? nil : identifier.gsub(/\D/, '').last(10)

      if !is_email && (normalized_phone.blank? || normalized_phone.length < 10)
        return render json: { error: "Please enter a valid 10-digit mobile number" }, status: :unprocessable_entity
      end

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
          country_code: params[:country_code].presence || ENV.fetch('DEFAULT_COUNTRY_CODE', '+91'),
          status: 'pending'
        )
      end

      OtpService.send_otp(account)

      channel_name = account.phone.present? ? "WhatsApp" : "Email"
      render json: {
        message: "6-digit OTP sent successfully via #{channel_name}",
        flow: signup ? 'signup' : 'login',
        channel: channel_name.downcase
      }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def verify_otp
      identifier = params[:identifier].to_s.strip
      otp = params[:otp].to_s.strip

      if identifier.blank? || otp.blank?
        return render json: { error: "Identifier and OTP are required" }, status: :unprocessable_entity
      end

      is_email = identifier.include?('@')
      normalized_phone = is_email ? nil : identifier.gsub(/\D/, '').last(10)

      account = is_email ?
                  Account.find_by(email: identifier.downcase) :
                  Account.find_by(phone: normalized_phone)

      return render json: { error: 'Invalid or expired OTP' }, status: :unauthorized unless account&.otp_valid?(otp)

      account.clear_otp!
      
      # Send login notification (only for existing accounts, not signup)
      is_signup = account.status == 'pending'

      if is_signup
        account.update(status: 'active')
        AccountMailer.signup_email(account).deliver_now if account.email.present?
      else
        AccountMailer.login_notification(account).deliver_now if account.email.present?
      end
      
      token = JsonWebToken.encode(user_id: account.id, user_type: 'Account')

      render json: {
        message: is_signup ? 'Signup successful' : 'Login successful',
        token: token,
        account: serialize_data(account, AccountSerializer)
      }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def google_login
      result = GoogleTokenVerifier.verify(params[:id_token])

      return render json: { error: 'Invalid Google token' }, status: :unauthorized unless result

      account = Account.find_or_initialize_by(email: result[:email])

      if account.new_record?
        generated_password = SecureRandom.urlsafe_base64(12)
        account.assign_attributes(
          email: result[:email],
          first_name: result[:first_name],
          last_name: result[:last_name],
          provider: 'google',
          provider_uid: result[:uid],
          google_signup: true,
          status: 'active',
          password: generated_password,
          password_confirmation: generated_password
        )
        account.save!
      else
        account.update!(
          provider: 'google',
          provider_uid: result[:uid],
          google_signup: true
        )
      end

      token = JsonWebToken.encode(user_id: account.id, user_type: 'Account')

      render json: {
        token: token,
        account: serialize_data(account, AccountSerializer)
      }
    end
  end
end
