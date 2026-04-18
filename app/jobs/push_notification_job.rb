class PushNotificationJob < ApplicationJob
  queue_as :default

  def perform(app_notification_id)
    notification = Notification.find_by(id: app_notification_id)
    return unless notification

    PushNotificationService.new.deliver(notification)
  end
end
