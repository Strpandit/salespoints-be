class DealerPayoutMailer < ApplicationMailer
  default from: "Sales Points <salespointecom@gmail.com>"

  def dealer_request_confirmation(payout_id)
    @payout = DealerPayout.includes(:dealer).find(payout_id)
    return if @payout.dealer.email.blank?
    attach_gst_invoice_if_present

    mail(to: @payout.dealer.email, subject: "Payout request #{@payout.request_number} submitted")
  end

  def admin_new_request(payout_id, admin_email)
    @payout = DealerPayout.includes(:dealer).find(payout_id)
    return if admin_email.blank?
    attach_gst_invoice_if_present

    mail(to: admin_email, subject: "New dealer payout request #{@payout.request_number}")
  end

  def dealer_status_update(payout_id)
    @payout = DealerPayout.includes(:dealer).find(payout_id)
    return if @payout.dealer.email.blank?

    mail(to: @payout.dealer.email, subject: "Payout request #{@payout.request_number} updated")
  end

  def admin_status_update(payout_id, admin_email)
    @payout = DealerPayout.includes(:dealer).find(payout_id)
    return if admin_email.blank?

    mail(to: admin_email, subject: "Payout request #{@payout.request_number} is now #{@payout.status.to_s.humanize}")
  end

  private

  def format_amount(value)
    format("%.2f", value.to_d)
  end

  def attach_gst_invoice_if_present
    return unless @payout.gst_invoice.attached?

    attachments[@payout.gst_invoice.filename.to_s] = {
      mime_type: @payout.gst_invoice.content_type,
      content: @payout.gst_invoice.download
    }
  end
end
