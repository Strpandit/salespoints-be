class CheckPayoutTransferStatusJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(payout_id) { payout_id }, group: "payout_status"

  retry_on StandardError, attempts: 5, wait: :exponentially_longer

  def perform(payout_id)
    payout = DealerPayout.find_by(id: payout_id)
    return if payout.blank?

    return unless payout.processing?
    return if payout.payment_reference.blank?

    service = SettlementAndPayoutAutomationService.new
    service.check_transfer_status!(payout: payout)
    
    Rails.logger.info("Payout transfer status checked for payout #{payout_id}")
  rescue StandardError => e
    Rails.logger.error("Transfer status check job failed for payout #{payout_id}: #{e.message}")
    raise
  end
end
