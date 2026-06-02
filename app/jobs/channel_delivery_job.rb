class ChannelDeliveryJob < ApplicationJob
  queue_as :default

  def perform(notification_id)
    notification = Notification.find_by(id: notification_id)
    return unless notification

    MetaWhatsappCloudService.new.deliver(notification)
    PlivoChannelService.new.deliver(notification)
  end
end
