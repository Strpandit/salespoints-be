class B2bOrderOffer < ApplicationRecord
  STATUSES = %w[open accepted rejected expired cancelled].freeze
  WHATSAPP_STATUSES = %w[pending sent delivered read failed replied].freeze

  belongs_to :b2b_order
  belongs_to :dealer
  belongs_to :notification, optional: true
  has_many :whatsapp_webhook_events, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :whatsapp_status, inclusion: { in: WHATSAPP_STATUSES }
  validates :accept_token, :reject_token, presence: true, uniqueness: true

  scope :open_state, -> { where(status: "open") }
  scope :active_state, -> { where(status: %w[open accepted]) }
  scope :expirable, -> { open_state.where.not(expires_at: nil).where("expires_at <= ?", Time.current) }

  def item_id_values
    Array(item_ids).map(&:to_i).uniq
  end

  def open?
    status == "open"
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end
end
