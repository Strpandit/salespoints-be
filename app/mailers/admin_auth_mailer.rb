class AdminAuthMailer < ApplicationMailer
  def admin_created(admin, password)
    @admin = admin
    @password = password
    @login_url = ENV['ADMIN_LOGIN_URL'] || 'http://localhost:3000/admin/login'
    mail(to: admin.email, subject: "SalesPoints Admin Account Created - Credentials Inside")
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
end
