class DealerBroadcastTracker < ApplicationRecord
  belongs_to :dealer
  belongs_to :b2b_order
end
