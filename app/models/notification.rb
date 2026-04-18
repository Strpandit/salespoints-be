class Notification < ApplicationRecord
  belongs_to :receiver, polymorphic: true
  belongs_to :actor, polymorphic: true, optional: true
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :notification_type, :title, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :unread, -> { where(read_at: nil) }

  after_commit :enqueue_remote_channels, on: :create

  def mark_read!
    return if read_at.present?

    update!(read_at: Time.current)
  end

  private

  def enqueue_remote_channels
    PushNotificationJob.perform_later(id)
    ChannelDeliveryJob.perform_later(id)
  end

  public

  def visible_in_app?
    payload.fetch("visible_in_app", true) != false
  end

  def delivery_channels
    raw = payload["delivery_channels"]
    raw.is_a?(Hash) ? raw.stringify_keys : {}
  end
end
