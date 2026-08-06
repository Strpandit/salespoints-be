class SmsService
  def self.send_sms(phone, message)
    return false if phone.blank?

    MetaWhatsappCloudService.new.send_text_message(to: phone, body: message)
    true
  rescue StandardError => e
    Rails.logger.error("WhatsApp message delivery failed: #{e.message}")
    false
  end
end
