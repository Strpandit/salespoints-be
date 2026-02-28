class DealerAuthMailer < ApplicationMailer
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
