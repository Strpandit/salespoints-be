class OtpService
  MAX_ATTEMPTS = 5
  COOLDOWN     = 30.seconds
  OTP_TTL      = 5.minutes

  def self.send_otp(account)
    if account.otp_sent_at && account.otp_sent_at > COOLDOWN.ago
      raise StandardError, "Please wait 30 seconds before requesting another OTP"
    end

    attempts = Rails.cache.read(otp_attempt_key(account)) || 0
    raise StandardError, "Too many OTP requests. Please try again in 5 minutes." if attempts >= MAX_ATTEMPTS

    otp = rand(100000..999999).to_s

    account.update!(
      otp_pin: otp,
      otp_sent_at: Time.current
    )

    Rails.cache.write(
      otp_attempt_key(account),
      attempts + 1,
      expires_in: OTP_TTL
    )

    send_via_channel(account, otp)
  end

  def self.send_via_channel(account, otp)
    if account.phone.present?
      destination = formatted_phone(account.phone, account.country_code)
      MetaWhatsappCloudService.new.send_login_otp(to: destination, otp: otp)
    elsif account.email.present?
      AccountMailer.send_otp(account, otp).deliver_now
    else
      raise StandardError, "No phone number or email registered for this account"
    end
  end

  private

  def self.formatted_phone(phone, country_code)
    cc = country_code.to_s.strip.presence || "+91"
    cc = "+#{cc.delete_prefix('+')}" unless cc.start_with?("+")
    raw = phone.to_s.gsub(/\D/, "").last(10)
    "#{cc}#{raw}".delete_prefix("+")
  end

  def self.otp_attempt_key(account)
    "otp_attempts:#{account.id}"
  end
end
