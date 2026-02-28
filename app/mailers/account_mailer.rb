class AccountMailer < ApplicationMailer
  default from: 'no-reply@salespoints.com'

  def send_otp(account, otp)
    @account = account
    @otp = otp
    mail(to: account.email, subject: "Your OTP Code")
  end

  def set_password(account)
    @url = "#{ENV['FRONTEND_URL']}/set-password?token=#{account.reset_password_token}"
    mail(to: account.email, subject: "Set Your Password")
  end

  def signup_email(account)
    @account = account
    mail(to: account.email, subject: "Welcome to SalesPoints - Account Created") if account.email.present?
  end

  def login_notification(account)
    @account = account
    @login_time = Time.now.strftime("%B %d, %Y at %I:%M %p")
    mail(to: account.email, subject: "Login Notification - SalesPoints") if account.email.present?
  end

  def account_deleted(email)
    @email = email
    mail(to: email, subject: "SalesPoints Account Deleted")
  end

  def account_blocked(account)
    @account = account
    mail(to: account.email, subject: "Account Status Update - SalesPoints") if account.email.present?
  end

  def account_unblocked(account)
    @account = account
    mail(to: account.email, subject: "Account Reactivated - SalesPoints") if account.email.present?
  end
end
