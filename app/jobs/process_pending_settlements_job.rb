class ProcessPendingSettlementsJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, group: "pending_settlements"

  retry_on StandardError, attempts: 3, wait: :exponentially_longer

  def perform
    result = SettlementAndPayoutAutomationService.process_pending_settlements!
    
    Rails.logger.info("Settlement Processing Job completed: #{result[:message]}")
    
    if result[:failed] > 0
      Rails.logger.warn("Settlement processing had #{result[:failed]} failures")
    end

    result
  rescue StandardError => e
    Rails.logger.error("Settlement Processing Job failed: #{e.message}\n#{e.backtrace.join("\n")}")
    raise
  end
end
