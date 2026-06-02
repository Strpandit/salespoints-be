class SupportTicket < ApplicationRecord
  # Associations
  belongs_to :account, optional: true
  belongs_to :dealer, optional: true
  belongs_to :admin_user, optional: true
  belongs_to :assigned_to, class_name: 'AdminUser', foreign_key: 'assigned_to_id', optional: true
  has_many :messages, class_name: 'TicketMessage', dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy

  # Validations
  validates :ticket_number, presence: true, uniqueness: true
  validates :subject, presence: true
  validates :description, presence: true
  validates :category, presence: true, inclusion: { in: %w(order_issue payment product account general other) }
  validates :priority, inclusion: { in: %w(low medium high urgent) }
  validates :status, inclusion: { in: %w(open in_progress waiting_customer resolved closed) }
  validates :user_type, inclusion: { in: %w(customer dealer admin) }

  # Scopes
  scope :open, -> { where(status: %w(open in_progress waiting_customer)) }
  scope :resolved, -> { where(status: 'resolved') }
  scope :closed, -> { where(status: 'closed') }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(status: status) if status.present? }
  scope :by_priority, ->(priority) { where(priority: priority) if priority.present? }
  scope :by_category, ->(category) { where(category: category) if category.present? }
  scope :assigned_to_admin, ->(admin_id) { where(assigned_to_id: admin_id) }
  scope :for_user, ->(account_id) { where(account_id: account_id, user_type: 'customer') }
  scope :for_dealer, ->(dealer_id) { where(dealer_id: dealer_id, user_type: 'dealer') }
  scope :for_admin, ->(admin_id) { where(admin_user_id: admin_id, user_type: 'admin') }

  # Callbacks
  before_create :generate_ticket_number

  # Methods
  def generate_ticket_number
    timestamp = Time.current.strftime('%y%m%d')
    random_suffix = SecureRandom.hex(3).upcase
    self.ticket_number = "TKT-#{timestamp}-#{random_suffix}"
  end

  def requester_name
    case user_type
    when 'customer'
      account&.full_name.presence || 'Customer'
    when 'dealer'
      dealer&.full_name.presence || dealer&.dealer_code || 'Dealer'
    when 'admin'
      admin_user&.full_name.presence || admin_user&.email || 'Admin'
    else
      'Unknown'
    end
  end

  def requester_email
    case user_type
    when 'customer'
      account&.email
    when 'dealer'
      dealer&.email
    when 'admin'
      admin_user&.email
    end
  end

  def add_message(sender_type, message, sender_user)
    msg = messages.build(
      sender_type: sender_type,
      message: message
    )

    case sender_type
    when 'customer'
      msg.account = sender_user
    when 'dealer'
      msg.dealer = sender_user
    when 'admin'
      msg.admin_user = sender_user
    end

    msg.save!
    msg
  end

  def resolve(resolution_summary)
    update!(
      status: 'resolved',
      resolution_summary: resolution_summary,
      resolved_at: Time.current
    )
  end

  def mark_as_closed
    update!(status: 'closed')
  end

  def assign_to_admin(admin_user)
    update!(assigned_to: admin_user, status: 'in_progress')
  end

  def category_display
    {
      'order_issue' => 'Order Issue',
      'payment' => 'Payment Problem',
      'product' => 'Product Inquiry',
      'account' => 'Account Help',
      'general' => 'General Question',
      'other' => 'Other'
    }[category] || category
  end

  def priority_color
    {
      'low' => 'gray',
      'medium' => 'blue',
      'high' => 'orange',
      'urgent' => 'red'
    }[priority]
  end

  def status_color
    {
      'open' => 'gray',
      'in_progress' => 'blue',
      'waiting_customer' => 'yellow',
      'resolved' => 'green',
      'closed' => 'slate'
    }[status]
  end
end
