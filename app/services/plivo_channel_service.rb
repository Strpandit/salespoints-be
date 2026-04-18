require 'net/http'
require 'uri'
require 'json'

# Sends SMS and WhatsApp messages through Plivo.
# ENV: PLIVO_AUTH_ID, PLIVO_AUTH_TOKEN, PLIVO_SMS_FROM (+E.164)
# Optional: PLIVO_WHATSAPP_FROM (whatsapp:+<number>)
class PlivoChannelService
  BASE = 'https://api.plivo.com/v1/Account'.freeze

  def deliver(notification)
    return unless configured?

    to = e164_for(notification.receiver)
    return if to.blank?

    text = [notification.title, notification.body].compact.join(' - ').truncate(1_500)
    channels = notification.delivery_channels

    send_sms(to, text) unless channels.key?('sms') && channels['sms'] == false
    return if whatsapp_from.blank? || (channels.key?('whatsapp') && channels['whatsapp'] == false)

    send_whatsapp(to, text)
  rescue StandardError => e
  end

  def configured?
    auth_id.present? && auth_token.present? && sms_from.present?
  end

  private

  def auth_id
    ENV['PLIVO_AUTH_ID'].to_s.presence
  end

  def auth_token
    ENV['PLIVO_AUTH_TOKEN'].to_s.presence
  end

  def sms_from
    ENV['PLIVO_SMS_FROM'].to_s.presence
  end

  def whatsapp_from
    ENV['PLIVO_WHATSAPP_FROM'].to_s.presence
  end

  def e164_for(receiver)
    phone = receiver.try(:phone).to_s.gsub(/\s+/, '')
    return nil if phone.blank?

    cc = receiver.try(:country_code).to_s.strip
    cc = '+91' if cc.blank?
    cc = "+#{cc.delete_prefix('+')}" unless cc.start_with?('+')

    combined = "#{cc}#{phone.gsub(/\A\+/, '')}"
    parsed = Phonelib.parse(combined)
    parsed.valid? ? parsed.e164 : nil
  end

  def send_sms(to, body)
    uri = URI("#{BASE}/#{auth_id}/Message/")
    request = Net::HTTP::Post.new(uri)
    request.basic_auth(auth_id, auth_token)
    request.set_form_data(
      Src: sms_from,
      Dst: to,
      Text: body
    )
    response = http_client(uri).request(request)
    response.is_a?(Net::HTTPSuccess)
  end

  def send_whatsapp(to, body)
    wa_to = to.start_with?('whatsapp:') ? to : "whatsapp:#{to}"
    uri = URI("#{BASE}/#{auth_id}/Message/")
    request = Net::HTTP::Post.new(uri)
    request.basic_auth(auth_id, auth_token)
    request.set_form_data(
      Src: whatsapp_from,
      Dst: wa_to,
      Text: body
    )
    response = http_client(uri).request(request)
    response.is_a?(Net::HTTPSuccess)
  end

  def http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 20
    http.open_timeout = 10
    http
  end
end