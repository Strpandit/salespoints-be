class DealerMailer < ApplicationMailer
  def welcome_email(dealer, password)
    @dealer = dealer
    @password = password
    @email = dealer.email
    mail(to: dealer.email, subject: "Welcome to SalesPoints - Dealer Account Created")
  end

  def approval_email(dealer)
    @dealer = dealer
    mail(to: dealer.email, subject: "🎉 Your SalesPoints Dealer Account is Approved!")
  end

  def rejection_email(dealer, reason = nil)
    @dealer = dealer
    @reason = reason
    mail(to: dealer.email, subject: "SalesPoints Dealer Account Status Update")
  end
end
