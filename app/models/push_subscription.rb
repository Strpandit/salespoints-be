class PushSubscription < ApplicationRecord
  belongs_to :subscriber, polymorphic: true

  validates :token, presence: true
end
