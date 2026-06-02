class TicketMessage < ApplicationRecord
  belongs_to :support_ticket
  belongs_to :account, optional: true
  belongs_to :dealer, optional: true
  belongs_to :admin_user, optional: true

  validates :message, presence: true
  validates :sender_type, presence: true, inclusion: { in: %w(customer dealer admin system) }

  scope :recent, -> { order(created_at: :asc) }
  scope :public_messages, -> { where(is_internal: false) }
  scope :internal_messages, -> { where(is_internal: true) }

  after_create :touch_ticket

  def sender
    case sender_type
    when 'admin'
      admin_user
    when 'customer'
      account
    when 'dealer'
      dealer
    end
  end

  def sender_name
    case sender_type
    when 'customer'
      sender&.full_name.presence || sender&.email || "Customer"
    when 'dealer'
      sender&.full_name.presence || sender&.dealer_code || sender&.email || "Dealer"
    when 'admin'
      sender&.full_name.presence || sender&.email || "Admin"
    else
      "#{sender_type.capitalize} User"
    end
  end

  private

  def touch_ticket
    support_ticket.update(messages_count: support_ticket.messages.count)
  end
end
