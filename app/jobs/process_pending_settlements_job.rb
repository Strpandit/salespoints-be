class ProcessPendingSettlementsJob
  include Sidekiq::Job

  sidekiq_options retry: 3, lock: :until_executed, on_conflict: :log

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
