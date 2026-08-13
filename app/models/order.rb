class Order < ApplicationRecord
  belongs_to :buyer, polymorphic: true
  belongs_to :seller_dealer, class_name: "Dealer", optional: true
  has_many :order_items, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :nullify
  has_many :return_requests, as: :requestable, dependent: :destroy
  has_many :dealer_ledger_entries, dependent: :nullify
  has_one :delivery_confirmation, -> { where(context: "original") }, as: :deliverable, class_name: "DeliveryConfirmation", dependent: :destroy
  has_one :replacement_delivery_confirmation, -> { where(context: "replacement") }, as: :deliverable, class_name: "DeliveryConfirmation", dependent: :destroy
  has_many :order_offers, dependent: :destroy
  has_many :order_broadcast_trackers, dependent: :destroy

  enum :status, {
    pending: "pending",
    processing: "processing",
    shipped: "shipped",
    delivered: "delivered",
    cancelled: "cancelled",
    return_requested: "return_requested",
    return_approved: "return_approved",
    return_in_transit: "return_in_transit",
    returned: "returned",
    replacement_requested: "replacement_requested",
    replacement_approved: "replacement_approved",
    replacement_shipped: "replacement_shipped",
    replacement_delivered: "replacement_delivered"
  }

  PAYMENT_METHODS = %w[cod online].freeze
  PAYMENT_STATUSES = %w[pending paid failed partially_refunded refunded].freeze
  SETTLEMENT_STATUSES = %w[on_hold pending partially_refunded settled refunded].freeze
  REFUND_STATUSES = %w[none partial completed].freeze

  validates :order_number, presence: true, uniqueness: true
  validates :buyer_type, :buyer_id, presence: true
  validates :payment_method, :payment_status, presence: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :settlement_status, inclusion: { in: SETTLEMENT_STATUSES }, allow_blank: false
  validates :refund_status, inclusion: { in: REFUND_STATUSES }, allow_blank: false
  validates :expires_at, presence: true, if: -> { status == "pending" && seller_dealer_id.nil? }

  before_validation :assign_order_number, on: :create
  before_validation :set_placed_at, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :pending_b2c, -> { where(status: "pending", seller_dealer_id: nil) }

  def total_items
    order_items.sum(:quantity)
  end

  def can_transition_to?(next_status)
    return false if next_status.blank?

    allowed = {
      "pending" => %w[processing cancelled],
      "processing" => %w[shipped cancelled],
      "shipped" => %w[delivered cancelled],
      "delivered" => %w[return_requested replacement_requested],
      "return_requested" => %w[return_approved cancelled],
      "return_approved" => %w[return_in_transit cancelled],
      "return_in_transit" => %w[returned cancelled],
      "returned" => [],
      "replacement_requested" => %w[replacement_approved cancelled],
      "replacement_approved" => %w[replacement_shipped cancelled],
      "replacement_shipped" => %w[replacement_delivered cancelled],
      "replacement_delivered" => [],
      "cancelled" => []
    }

    allowed.fetch(status.to_s, []).include?(next_status.to_s)
  end

  def mark_payment_paid!(reference: nil, gateway_payload: {})
    update!(
      payment_status: "paid",
      payment_reference: reference.presence || payment_reference,
      payment_gateway_payload: payment_gateway_payload.merge(gateway_payload || {}),
      payment_confirmed_at: payment_confirmed_at || Time.current
    )
  end

  def mark_payment_failed!(gateway_payload: {})
    update!(
      payment_status: "failed",
      payment_gateway_payload: payment_gateway_payload.merge(gateway_payload || {})
    )
  end

  def mark_payment_refunded!(amount:, gateway_payload: {}, reason: nil)
    next_refund_amount = (refund_amount.to_d + BigDecimal(amount.to_s)).round(2)
    fully_refunded = next_refund_amount >= total_amount.to_d.round(2)
    refunds = Array(payment_gateway_payload["refunds"])

    update!(
      payment_status: fully_refunded ? "refunded" : "partially_refunded",
      refund_status: fully_refunded ? "completed" : "partial",
      refund_amount: next_refund_amount,
      refunded_at: Time.current,
      refund_reason: reason.presence || refund_reason,
      payment_gateway_payload: payment_gateway_payload.merge(
        "refunds" => refunds + [gateway_payload],
        "latest_refund" => gateway_payload
      )
    )
  end

  def refundable?
    payment_status.in?(%w[paid partially_refunded refunded]) && refundable_amount_remaining.positive?
  end

  def refundable_amount_remaining
    [(total_amount.to_d - refund_amount.to_d).round(2), 0.to_d].max
  end

  def return_window_open?
    return false unless delivered_at.present?
    return false if return_window_closes_at.blank?

    Time.current <= return_window_closes_at
  end

  def active_return_request?
    return_requests.where(request_type: "return", status: ReturnRequest::ACTIVE_STATUSES).exists?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def replacement_window_open?
    return false if delivered_at.blank?

    Time.current <= delivered_at + 48.hours
  end

  def payment_completed?
    payment_status == "paid"
  end

  def replacement_requested?
    return_requests.where(request_type: "replacement").exists?
  end

  def replacement_allowed?
    payment_completed? &&
      delivered? &&
      replacement_window_open? &&
      !replacement_requested?
  end

  def replacement_request
    return_requests
      .where(request_type: "replacement")
      .order(created_at: :desc)
      .first
  end

  private

  def assign_order_number
    return if order_number.present?
    
    self.order_number = generate_order_number
  end

  def generate_order_number
    date_prefix = Time.current.strftime("%d%m%Y")
    
    self.class.transaction do
      last_order = self.class.where("order_number LIKE ?", "SPIN#{date_prefix}%")
                             .order(order_number: :desc)
                             .lock
                             .first
      
      serial = if last_order.present?
                 last_order.order_number[-6..-1].to_i + 1
               else
                 1
               end
      
      "SPIN#{date_prefix}#{serial.to_s.rjust(6, '0')}"
    end
  end

  def set_placed_at
    self.placed_at ||= Time.current
  end
end
