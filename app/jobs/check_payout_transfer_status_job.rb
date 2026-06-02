class CheckPayoutTransferStatusJob
  include Sidekiq::Job

  sidekiq_options retry: 5, lock: :until_executed, on_conflict: :log

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
    raise if retries < max_retries
  end

  private

  def max_retries
    5
  end
end
