class ProcessDealerPayoutsJob
  include Sidekiq::Job

  sidekiq_options retry: 3, lock: :until_executed, on_conflict: :log

  def perform
    result = SettlementAndPayoutAutomationService.process_dealer_payouts!
    
    Rails.logger.info("Dealer Payout Processing Job completed: #{result[:message]}")
    
    if result[:failed] > 0
      Rails.logger.warn("Payout processing had #{result[:failed]} failures")
    end

    result
  rescue StandardError => e
    Rails.logger.error("Dealer Payout Processing Job failed: #{e.message}\n#{e.backtrace.join("\n")}")
    raise
  end
end
