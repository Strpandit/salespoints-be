class ProcessPendingSettlementsJob < ApplicationJob
  queue_as :default

  limits_concurrency(
    to: 1,
    key: ->(*) { "pending_settlements" }
  )

  retry_on StandardError, attempts: 3, wait: :exponentially_longer

  def perform
    result = SettlementAndPayoutAutomationService.process_pending_settlements!
    
    if result[:failed] > 0
      Rails.logger.warn("Settlement processing had #{result[:failed]} failures")
    end

    result
  end
end
