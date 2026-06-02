class DealerPayoutMailer < ApplicationMailer
  default from: "Sales Points <salespointecom@gmail.com>"

  def dealer_request_confirmation(payout_id)
    @payout = DealerPayout.includes(:dealer).find(payout_id)
    return if @payout.dealer.email.blank?

    mail(
      to: @payout.dealer.email,
      subject: "Payout request #{@payout.request_number} submitted",
      body: <<~BODY
        Hello #{@payout.dealer.full_name.presence || "Dealer"},

        Your payout request #{@payout.request_number} for Rs #{format_amount(@payout.amount)} has been submitted successfully.
        Status: #{@payout.status.to_s.humanize}

        We will notify you once an administrator reviews it.
      BODY
    )
  end

  def admin_new_request(payout_id, admin_email)
    @payout = DealerPayout.includes(:dealer).find(payout_id)
    return if admin_email.blank?

    mail(
      to: admin_email,
      subject: "New dealer payout request #{@payout.request_number}",
      body: <<~BODY
        A new dealer payout request has been submitted.

        Dealer: #{@payout.dealer.full_name.presence || @payout.dealer.dealer_code}
        Request: #{@payout.request_number}
        Amount: Rs #{format_amount(@payout.amount)}
        Status: #{@payout.status.to_s.humanize}
      BODY
    )
  end

  def dealer_status_update(payout_id)
    @payout = DealerPayout.includes(:dealer).find(payout_id)
    return if @payout.dealer.email.blank?

    mail(
      to: @payout.dealer.email,
      subject: "Payout request #{@payout.request_number} updated",
      body: <<~BODY
        Hello #{@payout.dealer.full_name.presence || "Dealer"},

        Your payout request #{@payout.request_number} is now #{@payout.status.to_s.humanize}.
        Amount: Rs #{format_amount(@payout.amount)}
        Payment reference: #{@payout.payment_reference.presence || "Pending"}
        Admin note: #{@payout.admin_note.presence || "NA"}
      BODY
    )
  end

  def admin_status_update(payout_id, admin_email)
    @payout = DealerPayout.includes(:dealer).find(payout_id)
    return if admin_email.blank?

    mail(
      to: admin_email,
      subject: "Payout request #{@payout.request_number} is now #{@payout.status.to_s.humanize}",
      body: <<~BODY
        Dealer payout request status changed.

        Dealer: #{@payout.dealer.full_name.presence || @payout.dealer.dealer_code}
        Request: #{@payout.request_number}
        Amount: Rs #{format_amount(@payout.amount)}
        Status: #{@payout.status.to_s.humanize}
        Payment reference: #{@payout.payment_reference.presence || "Pending"}
        Admin note: #{@payout.admin_note.presence || "NA"}
      BODY
    )
  end

  private

  def format_amount(value)
    format("%.2f", value.to_d)
  end
end
