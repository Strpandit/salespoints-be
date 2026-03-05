module Api
  class ApplicationController < ActionController::API
    before_action :authenticate_request!
    skip_before_action :verify_authenticity_token

    attr_reader :current_user, :current_user_type

    private

    def authenticate_request!
      token = request.headers['Authorization']&.split(' ')&.last
      return unauthorized('Missing token') unless token

      payload = JsonWebToken.decode(token)
      return unauthorized('Invalid token') unless payload

      @current_user_type = payload[:user_type]
      @current_user = find_user(payload)

      return unauthorized('Invalid token') unless @current_user
    rescue JWT::ExpiredSignature
      unauthorized('Token has expired')
    rescue JWT::DecodeError
      unauthorized('Invalid token')
    end

    def find_user(payload)
      case payload[:user_type]
      when 'Account'
        Account.find_by(id: payload[:user_id])
      when 'Dealer'
        Dealer.find_by(id: payload[:user_id])
      when 'AdminUser'
        AdminUser.find_by(id: payload[:user_id])
      else
        nil
      end
    end

    def unauthorized(message)
      render json: { error: message }, status: :unauthorized and return
    end

    def current_admin
      current_user if current_user_type == 'AdminUser'
    end

    def current_dealer
      current_user if current_user_type == 'Dealer'
    end

    def current_account
      current_user if current_user_type == 'Account'
    end
  end
end