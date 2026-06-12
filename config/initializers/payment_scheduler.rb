# # config/initializers/scheduler.rb
# # This file configures Sidekiq cron jobs for automated payment flow processing

# return if Rails.env.test?

# require "sidekiq-scheduler"

# # Process pending settlements every 30 minutes
# # This checks orders that are 7+ days post-delivery and have no active return requests
# #Sidekiq.configure_server do |config|
#  # config.server_middleware do |chain|
#   #  chain.add SidekiqScheduler::MiddleWare
#  # end
# #end if Sidekiq.server?

# # Define recurring jobs using Sidekiq::Cron
# if defined?(Sidekiq::Cron)
#   Sidekiq::Cron::Job.create!(
#     name: "process_pending_settlements",
#     cron: "*/30 * * * *", # Every 30 minutes
#     class: "ProcessPendingSettlementsJob",
#     active: ENV["ENABLE_SETTLEMENT_AUTOMATION"] == "true"
#   )

#   Sidekiq::Cron::Job.create!(
#     name: "process_dealer_payouts",
#     cron: "0 2 * * *", # Daily at 2 AM
#     class: "ProcessDealerPayoutsJob",
#     active: ENV["ENABLE_PAYOUT_AUTOMATION"] == "true"
#   )

#   # Retry failed payment webhooks
#   Sidekiq::Cron::Job.create!(
#     name: "retry_failed_webhooks",
#     cron: "0 * * * *", # Hourly
#     class: "RetryFailedWebhooksJob",
#     active: ENV["ENABLE_WEBHOOK_RETRY"] == "true"
#   )

#   Sidekiq::Cron::Job.create!(
#     name: "cleanup_expired_b2b_offers",
#     cron: "*/5 * * * *", # Every 5 minutes
#     class: "B2bOrderOfferCleanupJob",
#     active: ENV.fetch("ENABLE_B2B_OFFER_CLEANUP", "true") == "true"
#   )
# end

Rails.logger.info("Payment automation scheduler initialized")