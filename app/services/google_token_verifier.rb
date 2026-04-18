require "json"
require "net/http"
require "uri"

class GoogleTokenVerifier
  TOKEN_INFO_URL = "https://oauth2.googleapis.com/tokeninfo".freeze
  VALID_ISSUERS = %w[accounts.google.com https://accounts.google.com].freeze

  class << self
    def verify(id_token)
      client_id = ENV["GOOGLE_CLIENT_ID"].to_s.strip
      token = id_token.to_s.strip

      if client_id.empty?
        return nil
      end

      return nil if token.empty?

      payload = fetch_token_info(token)
      return nil unless payload
      return nil unless payload["aud"].to_s == client_id
      return nil unless VALID_ISSUERS.include?(payload["iss"].to_s)
      return nil unless ActiveModel::Type::Boolean.new.cast(payload["email_verified"])

      {
        uid: payload["sub"],
        email: payload["email"].to_s.downcase,
        first_name: payload["given_name"],
        last_name: payload["family_name"],
        name: payload["name"]
      }
    rescue StandardError => e
      nil
    end

    private

    def fetch_token_info(id_token)
      uri = URI("#{TOKEN_INFO_URL}?id_token=#{URI.encode_www_form_component(id_token)}")
      response = Net::HTTP.get_response(uri)
      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      nil
    end
  end
end
