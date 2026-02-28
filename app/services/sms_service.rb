class SmsService
  def self.send_sms(phone, message)
    Rails.logger.info("[SmsService] Sending SMS to #{phone}: #{message}")
    # If TWILIO_ACCOUNT_SID is provided, try using Twilio
    if ENV['TWILIO_ACCOUNT_SID'].present?
      begin
        require 'twilio-ruby'
        client = Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])
        from = ENV['TWILIO_FROM'] || '+15005550006'
        client.messages.create(from: from, to: phone, body: message)
      rescue LoadError => e
        Rails.logger.warn('[SmsService] twilio-ruby gem not installed; SMS not sent via Twilio')
      rescue => e
        Rails.logger.error("[SmsService] Error sending SMS via Twilio: #{e.message}")
      end
    end
    true
  end
end
