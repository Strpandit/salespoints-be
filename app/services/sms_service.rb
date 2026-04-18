require 'net/http'
require 'uri'
require 'json'

class SmsService
  def self.send_sms(phone, message)
    return false unless configured?

    uri = URI("https://api.plivo.com/v1/Account/#{auth_id}/Message/")
    request = Net::HTTP::Post.new(uri)
    request.basic_auth(auth_id, auth_token)
    request.set_form_data(
      Src: sms_from,
      Dst: normalize_phone(phone),
      Text: message
    )

    response = http_client(uri).request(request)
    response.is_a?(Net::HTTPSuccess)
  rescue StandardError => e
    false
  end

  def self.configured?
    auth_id.present? && auth_token.present? && sms_from.present?
  end

  def self.auth_id
    ENV['PLIVO_AUTH_ID'].to_s.presence
  end

  def self.auth_token
    ENV['PLIVO_AUTH_TOKEN'].to_s.presence
  end

  def self.sms_from
    ENV['PLIVO_SMS_FROM'].to_s.presence
  end

  def self.normalize_phone(phone)
    phone.to_s.gsub(/\s+/, '')
  end

  def self.http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 20
    http.open_timeout = 10
    http
  end
end
