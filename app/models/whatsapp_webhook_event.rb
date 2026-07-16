class WhatsappWebhookEvent < ApplicationRecord
  belongs_to :b2b_order_offer, optional: true
  belongs_to :order_offer, optional: true
  belongs_to :notification, optional: true

  validates :provider, :event_type, :event_key, :direction, presence: true
  validates :event_key, uniqueness: true

  def offer
    b2b_order_offer || order_offer
  end
end
