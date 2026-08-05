require "cgi"

class AdminAuthMailer < ApplicationMailer
  def forgot_password_otp(admin)
    @admin = admin
    @otp = admin.otp_pin
    @expires_in_minutes = 10
    mail(to: admin.email, subject: "Admin Password Reset OTP - SalesPoints")
  end

  def login_otp(admin)
    @admin = admin
    @otp = admin.otp_pin
    @expires_in_minutes = 10
    mail(to: admin.email, subject: "Verify your profile - SalesPoints")
  end

  def signup_otp(admin)
    @admin = admin
    @otp = admin.otp_pin
    @expires_in_minutes = 10
    base_url = ENV['FRONTEND_URL'] || 'https://salespoints.in'
    token_param = admin.signup_token.presence || admin.generate_signup_token!
    @verify_url = "#{base_url}/admin/signup-verify-otp?token=#{token_param}"
    @login_url = ENV['ADMIN_LOGIN_URL'] || 'https://salespoints.in/admin/login'
    mail(to: admin.email, subject: "Admin Onboarding OTP - SalesPoints")
  end

  def admin_created(admin, password)
    @admin = admin
    @password = password
    @login_url = ENV['ADMIN_LOGIN_URL'] || 'https://salespoints.in/admin/login'
    mail(to: admin.email, subject: "SalesPoints Admin Account Created - Credentials Inside")
  end

  def onboarding_approval_request(admin, approver_email)
    @admin = admin
    @reviewer_portal_url = ENV['ADMIN_LOGIN_URL'] || 'https://salespoints.in/admin/login'
    attach_offer_letter(@admin)
    mail(to: approver_email, subject: "Approval Required: New Admin Onboarding - #{@admin.full_name}")
  end

  def onboarding_approved(admin)
    @admin = admin
    @login_url = ENV['ADMIN_LOGIN_URL'] || 'https://salespoints.in/admin/login'
    attach_offer_letter(@admin)
    mail(to: admin.email, subject: "SalesPoints Admin Onboarding Approved - Offer Letter Attached")
  end

  def admin_login_notification(admin)
    @admin = admin
    @login_time = Time.now.strftime("%B %d, %Y at %I:%M %p")
    @ip_address = 'System'
    mail(to: admin.email, subject: "🔐 Admin Login Notification - SalesPoints")
  end

  def password_reset_confirmation(admin)
    @admin = admin
    @reset_time = Time.now.strftime("%B %d, %Y at %I:%M %p")
    mail(to: admin.email, subject: "Password Reset Confirmation - SalesPoints")
  end

  private

  def attach_offer_letter(admin)
    attachments["salespoints_offer_letter_#{admin.id}.pdf"] = {
      mime_type: "application/pdf",
      content: AdminOfferLetterPdf.new(admin).render
    }
  end
end
