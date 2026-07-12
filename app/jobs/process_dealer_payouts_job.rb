class ProcessDealerPayoutsJob < ApplicationJob
  queue_as :default

 limits_concurrency( to: 1, key: ->(*) {"dealer_payouts"})

  retry_on StandardError, attempts: 3, wait: :exponentially_longer

  def perform
    result = SettlementAndPayoutAutomationService.process_dealer_payouts!
    
    if result[:failed] > 0
      Rails.logger.warn("Payout processing had #{result[:failed]} failures")
    end

    result
  end
end
