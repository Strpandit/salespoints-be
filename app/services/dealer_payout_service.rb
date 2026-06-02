class DealerPayoutService
  def initialize(dealer:)
    @dealer = dealer
  end

  def request!(amount:, note: nil)
    value = BigDecimal(amount.to_s).round(2)
    raise StandardError, "Payout amount must be greater than 0" unless value.positive?
    raise StandardError, "Insufficient settlement balance" if value > @dealer.settlement_balance.to_d

    profile = @dealer.dealer_profile
    raise StandardError, "Dealer bank details are incomplete" if profile.blank? || profile.bank_name.blank? || profile.bank_account_number.blank? || profile.ifsc_code.blank?

    payout = DealerPayout.create!(
      dealer: @dealer,
      amount: value,
      bank_name: profile.bank_name,
      bank_account_number: profile.bank_account_number,
      ifsc_code: profile.ifsc_code,
      account_holder_name: @dealer.full_name.presence || profile.business_name,
      admin_note: note,
      metadata: {
        dealer_profile_id: profile.id,
        business_name: profile.business_name
      }
    )
    DealerPayoutNotificationService.request_created!(payout)
    payout
  end

  def approve!(payout:, admin:, note: nil)
    raise StandardError, "Only pending payouts can be approved" unless payout.pending?

    payout.update!(
      status: "approved",
      approved_at: Time.current,
      approved_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin)
  end

  def reject!(payout:, admin:, note:)
    raise StandardError, "Only pending payouts can be rejected" unless payout.pending?

    payout.update!(
      status: "rejected",
      rejected_at: Time.current,
      approved_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin)
  end

  def mark_processing!(payout:, admin:, note: nil)
    raise StandardError, "Only approved payouts can move to processing" unless payout.approved?

    payout.update!(
      status: "processing",
      processing_at: Time.current,
      processed_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin)
  end

  def mark_paid!(payout:, admin:, payment_reference:, payment_mode:, note: nil)
    raise StandardError, "Only approved or processing payouts can be paid" unless payout.status.in?(%w[approved processing])

    Dealer.transaction do
      locked_payout = DealerPayout.lock.find(payout.id)
      locked_dealer = Dealer.lock.find(locked_payout.dealer_id)
      raise StandardError, "Dealer settlement balance is insufficient" if locked_payout.amount.to_d > locked_dealer.settlement_balance.to_d

      DealerLedgerService.debit!(
        dealer: locked_dealer,
        amount: locked_payout.amount,
        entry_type: "payout_disbursement",
        description: "Payout disbursed for request #{locked_payout.request_number}",
        metadata: {
          payout_id: locked_payout.id,
          payment_reference: payment_reference,
          payment_mode: payment_mode,
          admin_id: admin.id
        }
      )

      locked_payout.update!(
        status: "paid",
        paid_at: Time.current,
        processing_at: locked_payout.processing_at || Time.current,
        processed_by_admin: admin,
        payment_reference: payment_reference,
        payment_mode: payment_mode,
        admin_note: [locked_payout.admin_note, note].compact.join("\n").presence
      )
      DealerPayoutNotificationService.status_updated!(locked_payout.reload, actor: admin)
    end
  end

  def mark_failed!(payout:, admin:, note:)
    raise StandardError, "Only approved or processing payouts can fail" unless payout.status.in?(%w[approved processing])

    payout.update!(
      status: "failed",
      processed_by_admin: admin,
      admin_note: [payout.admin_note, note].compact.join("\n").presence
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin)
  end

  def cancel!(payout:)
    raise StandardError, "Only pending payouts can be cancelled" unless payout.pending?

    payout.update!(
      status: "cancelled",
      cancelled_at: Time.current
    )
    DealerPayoutNotificationService.status_updated!(payout.reload, actor: @dealer)
  end
end
