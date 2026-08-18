class DealerPayoutMailer < ApplicationMailer
  default from: ENV["MAILER_FROM"].presence || "noreply@salespoints.in"

  def request_created(payout_or_id)
    @payout = find_payout(payout_or_id)
    return unless @payout

    @dealer = @payout.dealer
    @admin_emails = admin_emails

    recipients = [@dealer.email].compact.concat(@admin_emails).uniq

    mail(
      to: recipients,
      subject: "[SalesPoints Payout] New Request Submitted - #{@payout.request_number} (₹#{@payout.amount})"
    )
  end

  def dealer_request_confirmation(payout_or_id)
    request_created(payout_or_id)
  end

  def admin_new_request(payout_or_id, admin_email = nil)
    @payout = find_payout(payout_or_id)
    return unless @payout

    @dealer = @payout.dealer
    recipients = admin_email.presence ? [admin_email] : admin_emails

    mail(
      to: recipients,
      subject: "[SalesPoints Admin] Action Required: New Payout Request #{@payout.request_number} (₹#{@payout.amount})"
    )
  end

  def status_updated(payout_or_id, actor: nil)
    @payout = find_payout(payout_or_id)
    return unless @payout

    @dealer = @payout.dealer
    @actor = normalize_actor(actor)
    @admin_emails = admin_emails

    subject_status = @payout.status.to_s.humanize.titleize
    recipients = [@dealer.email].compact.concat(@admin_emails).uniq

    mail(
      to: recipients,
      subject: "[SalesPoints Payout] Status Updated: #{subject_status} - #{@payout.request_number}"
    )
  end

  def dealer_status_update(payout_or_id)
    status_updated(payout_or_id)
  end

  def admin_status_update(payout_or_id, admin_email = nil)
    @payout = find_payout(payout_or_id)
    return unless @payout

    @dealer = @payout.dealer
    recipients = admin_email.presence ? [admin_email] : admin_emails
    subject_status = @payout.status.to_s.humanize.titleize

    mail(
      to: recipients,
      subject: "[SalesPoints Admin Alert] Dealer Payout Status: #{subject_status} - #{@payout.request_number}"
    )
  end

  def payout_disbursed(payout_or_id)
    @payout = find_payout(payout_or_id)
    return unless @payout

    @dealer = @payout.dealer
    @admin_emails = admin_emails

    recipients = [@dealer.email].compact.concat(@admin_emails).uniq

    mail(
      to: recipients,
      subject: "[SalesPoints Payout] Payment Disbursed Successfully - #{@payout.request_number} (UTR: #{@payout.payment_reference})"
    )
  end

  def payout_failed(payout_or_id, error_message: nil)
    @payout = find_payout(payout_or_id)
    return unless @payout

    @dealer = @payout.dealer
    @error_message = error_message || @payout.admin_note
    @admin_emails = admin_emails

    recipients = [@dealer.email].compact.concat(@admin_emails).uniq

    mail(
      to: recipients,
      subject: "[SalesPoints Payout Action Required] Payment Failed - #{@payout.request_number}"
    )
  end

  private

  def find_payout(payout_or_id)
    payout_or_id.is_a?(DealerPayout) ? payout_or_id : DealerPayout.find_by(id: payout_or_id)
  end

  def admin_emails
    super_admins = AdminUser.where(is_super_admin: true).pluck(:email).compact.select(&:present?)
    active_admins = AdminUser.where(is_active: true).pluck(:email).compact.select(&:present?)
    combined = (super_admins + active_admins).uniq
    combined.presence || [ENV["SUPER_ADMIN_EMAIL"].presence || "admin@salespoints.in"]
  end

  def normalize_actor(actor)
    return nil if actor.blank?
    if actor.is_a?(Hash)
      actor[:name] || actor["name"] || actor[:email] || actor["email"]
    elsif actor.respond_to?(:full_name)
      actor.full_name
    elsif actor.respond_to?(:email)
      actor.email
    else
      actor.to_s
    end
  end
end
