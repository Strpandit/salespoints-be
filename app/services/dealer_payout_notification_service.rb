class DealerPayoutNotificationService
  class << self
    def request_created!(payout)
      notify_dealer_request_created!(payout)
      notify_admins_request_created!(payout)
    end

    def status_updated!(payout, actor: nil)
      notify_dealer_status_updated!(payout, actor: actor)
      notify_admins_status_updated!(payout, actor: actor)
    end

    private

    def notify_dealer_request_created!(payout)
      NotificationService.deliver(
        recipient: payout.dealer,
        actor: payout.dealer,
        notifiable: payout,
        kind: "dealer_payout_requested",
        title: "Payout request submitted",
        message: "Your payout request #{payout.request_number} for Rs #{format_amount(payout.amount)} is awaiting admin review.",
        payload: payout_payload(payout),
        delivery_channels: { push: true, email: true, in_app: true }
      )
      DealerPayoutMailer.dealer_request_confirmation(payout.id).deliver_later if payout.dealer&.email.present?
    rescue => e
      Rails.logger.error("Error in notify_dealer_request_created!: #{e.message}")
    end

    def notify_admins_request_created!(payout)
      recipients = admin_recipients
      recipients.each do |admin|
        NotificationService.deliver(
          recipient: admin,
          actor: payout.dealer,
          notifiable: payout,
          kind: "admin_dealer_payout_requested",
          title: "New dealer payout request",
          message: "#{payout.dealer.full_name.presence || 'Dealer'} requested payout #{payout.request_number} for Rs #{format_amount(payout.amount)}.",
          payload: payout_payload(payout),
          delivery_channels: { push: true, email: true, in_app: true }
        )
      end

      # Send email to super admins / admins
      begin
        DealerPayoutMailer.admin_new_request(payout.id).deliver_now
      rescue => mail_err
        Rails.logger.warn("deliver_now failed, trying deliver_later: #{mail_err.message}")
        DealerPayoutMailer.admin_new_request(payout.id).deliver_later
      end
    rescue => e
      Rails.logger.error("Error in notify_admins_request_created!: #{e.message}")
    end

    def notify_dealer_status_updated!(payout, actor:)
      NotificationService.deliver(
        recipient: payout.dealer,
        actor: actor,
        notifiable: payout,
        kind: "dealer_payout_status_updated",
        title: "Payout request updated",
        message: "Your payout request #{payout.request_number} is now #{payout.status.humanize.downcase}.",
        payload: payout_payload(payout),
        delivery_channels: { push: true, email: true, in_app: true }
      )
      if payout.dealer&.email.present?
        begin
          DealerPayoutMailer.dealer_status_update(payout.id).deliver_now
        rescue => mail_err
          Rails.logger.warn("deliver_now failed, trying deliver_later: #{mail_err.message}")
          DealerPayoutMailer.dealer_status_update(payout.id).deliver_later
        end
      end
    rescue => e
      Rails.logger.error("Error in notify_dealer_status_updated!: #{e.message}")
    end

    def notify_admins_status_updated!(payout, actor:)
      recipients = admin_recipients
      recipients.each do |admin|
        NotificationService.deliver(
          recipient: admin,
          actor: actor,
          notifiable: payout,
          kind: "admin_dealer_payout_status_updated",
          title: "Dealer payout status changed",
          message: "Payout request #{payout.request_number} is now #{payout.status.humanize.downcase}.",
          payload: payout_payload(payout),
          delivery_channels: { push: true, email: true, in_app: true }
        )
      end

      # Send email to super admins / admins
      begin
        DealerPayoutMailer.admin_status_update(payout.id).deliver_now
      rescue => mail_err
        Rails.logger.warn("deliver_now failed, trying deliver_later: #{mail_err.message}")
        DealerPayoutMailer.admin_status_update(payout.id).deliver_later
      end
    rescue => e
      Rails.logger.error("Error in notify_admins_status_updated!: #{e.message}")
    end

    def payout_payload(payout)
      {
        payout_id: payout.id,
        request_number: payout.request_number,
        dealer_id: payout.dealer_id,
        dealer_name: payout.dealer&.full_name,
        amount: payout.amount.to_f,
        status: payout.status,
        payment_reference: payout.payment_reference
      }.compact
    end

    def admin_recipients
      active_admins = AdminUser.where(status: "active").to_a
      target = active_admins.select { |admin| admin.super_admin? || admin.can_access?(:orders, :write) || admin.can_access?(:payouts, :read) }
      target.presence || active_admins
    end

    def format_amount(value)
      format("%.2f", value.to_d)
    end
  end
end
