require "cgi"

class DealerAuthMailer < ApplicationMailer
  def forgot_password_otp(dealer)
    @dealer = dealer
    @otp = dealer.otp_pin
    @expires_in_minutes = 10
    mail(to: dealer.email, subject: "Dealer Password Reset OTP - SalesPoints")
  end

  def signup_otp(dealer)
    @dealer = dealer
    @otp = dealer.otp_pin
    @expires_in_minutes = 10
    base_url = ENV['FRONTEND_URL'] || 'https://salespoints.in'
    @verify_url = "#{base_url}/dealer/verify-otp?id=#{dealer.id}&email=#{CGI.escape(dealer.email || '')}"
    mail(to: dealer.email, subject: "Dealer Onboarding OTP - SalesPoints")
  end

  def dealer_login_notification(dealer)
    @dealer = dealer
    @login_time = Time.now.strftime("%B %d, %Y at %I:%M %p")
    mail(to: dealer.email, subject: "🔐 Dealer Login Notification - SalesPoints")
  end

  def password_reset_confirmation(dealer)
    @dealer = dealer
    @reset_time = Time.now.strftime("%B %d, %Y at %I:%M %p")
    mail(to: dealer.email, subject: "Password Reset Confirmation - SalesPoints")
  end
end
