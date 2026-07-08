class WhatsappOtpService
  def self.send_otp(phone_number, otp_pin)
    return if phone_number.blank?

    formatted_phone = format_phone_number(phone_number)

    MetaWhatsappCloudService.new.send_otp(
      to: formatted_phone,
      otp_pin: otp_pin,
    )
  end

  private

  def self.format_phone_number(phone)
    phone = phone.to_s.gsub(/\D/, '')

    phone = phone.gsub(/^0+/, '')

    if phone.length == 10
      "+91#{phone}"
    elsif phone.length == 11 && phone.start_with?('0')
      "+91#{phone[1..-1]}"
    elsif phone.length == 12 && phone.start_with?('91')
      "+#{phone}"
    else
      "+#{phone}"
    end
  end
end