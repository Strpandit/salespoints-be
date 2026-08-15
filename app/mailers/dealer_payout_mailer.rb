class DealerPayoutMailer < ApplicationMailer
  default from: ENV["MAILER_FROM"].presence || "noreply@salespoints.in"

  def request_created(payout)
    @payout = payout
    @dealer = payout.dealer
    @admin_emails = admin_emails

    mail(
      to: @dealer.email,
      cc: @admin_emails,
      subject: "[SalesPoints Payout] Request Received - #{@payout.request_number} (₹#{@payout.amount})"
    )
  end

  def status_updated(payout, actor: nil)
    @payout = payout
    @dealer = payout.dealer
    @actor = actor
    @admin_emails = admin_emails

    subject_status = @payout.status.to_s.humanize.titleize

    mail(
      to: @dealer.email,
      cc: @admin_emails,
      subject: "[SalesPoints Payout] Status Update: #{subject_status} - #{@payout.request_number}"
    )
  end

  def payout_disbursed(payout)
    @payout = payout
    @dealer = payout.dealer
    @admin_emails = admin_emails

    mail(
      to: @dealer.email,
      cc: @admin_emails,
      subject: "[SalesPoints Payout] Payment Disbursed Successfully - #{@payout.request_number} (UTR: #{@payout.payment_reference})"
    )
  end

  def payout_failed(payout, error_message: nil)
    @payout = payout
    @dealer = payout.dealer
    @error_message = error_message || payout.admin_note
    @admin_emails = admin_emails

    mail(
      to: @dealer.email,
      cc: @admin_emails,
      subject: "[SalesPoints Payout Action Required] Payment Failed - #{@payout.request_number}"
    )
  end

  private

  def admin_emails
    super_admins = AdminUser.where(is_super_admin: true).pluck(:email).compact
    super_admins.presence || [ENV["SUPER_ADMIN_EMAIL"].presence || "admin@salespoints.in"]
  end
end
