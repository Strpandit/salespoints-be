class OtpService
  MAX_ATTEMPTS = 5
  COOLDOWN     = 60.seconds
  OTP_TTL      = 5.minutes

  def self.send_otp(account)
    if account.otp_sent_at && account.otp_sent_at > COOLDOWN.ago
      raise StandardError, "Please wait before requesting another OTP"
    end

    attempts = Rails.cache.read(otp_attempt_key(account)) || 0
    raise StandardError, "Too many OTP requests" if attempts >= MAX_ATTEMPTS

    otp = rand.to_s[2..7]

    account.update!(
      otp_pin: otp,
      otp_sent_at: Time.current
    )

    Rails.cache.write(
      otp_attempt_key(account),
      attempts + 1,
      expires_in: 15.minutes
    )

    send_via_channel(account, otp)
  end

  def self.send_via_channel(account, otp)
    if account.email.present?
      AccountMailer.send_otp(account, otp).deliver_later
    else
      SmsService.send_sms(account.phone, "Your OTP is #{otp}")
    end
  end

  def self.otp_attempt_key(account)
    "otp_attempts:#{account.id}"
  end

end
