class B2bOrder < ApplicationRecord
  belongs_to :buyer_dealer, class_name: "Dealer"
  belongs_to :seller_dealer, class_name: "Dealer", optional: true
  belongs_to :buyer_payment_attempt, class_name: "PaymentAttempt", optional: true
  belongs_to :source, polymorphic: true, optional: true
  has_many :notifications, as: :notifiable, dependent: :destroy
  has_many :b2b_order_items, dependent: :destroy
  has_many :b2b_order_offers, dependent: :destroy
  has_many :return_requests, as: :requestable, dependent: :destroy
  has_many :dealer_broadcast_trackers, dependent: :destroy
  has_one :delivery_confirmation, -> { where(context: "original") }, as: :deliverable, class_name: "DeliveryConfirmation", dependent: :destroy
  has_one :replacement_delivery_confirmation, -> { where(context: "replacement") }, as: :deliverable, class_name: "DeliveryConfirmation", dependent: :destroy

  REQUEST_STATUSES = %w[pending_request accepted_request rejected_request expired_request].freeze
  ORDER_STATUSES = %w[pending_request pending_payment paid confirmed shipped delivered cancelled return_requested return_approved return_in_transit returned replacement_requested replacement_approved replacement_shipped replacement_delivered].freeze
  PAYMENT_METHODS = %w[cod online].freeze
  PAYMENT_STATUSES = %w[pending paid failed].freeze

  validates :request_status, inclusion: { in: REQUEST_STATUSES }, allow_nil: true
  validates :status, inclusion: { in: ORDER_STATUSES }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :requested_radius_km, numericality: { greater_than: 0 }
  # validates :reference_number, presence: true, uniqueness: true

  scope :pending_requests, -> { where(request_status: "pending_request", status: ["pending_request", "pending_payment"]) }
  scope :accepted_requests, -> { where(request_status: "accepted_request") }
  scope :pending_payments, -> { where(status: "pending_payment") }
  scope :from_wholesaler_post, -> { where(source_type: 'WholesalerPost') }
  scope :direct_buy, -> { where(is_direct_buy: true) }

  before_validation :assign_payment_token, on: :create
  before_validation :set_reference_number, on: :create
  before_validation :sync_billing_address

  private

  def sync_billing_address
    self.billing_address = shipping_address if shipping_address.present?
  end

  public

  def wholesaler_post_id
    return source_id if source_type == "WholesalerPost"

    if b2b_order_items.loaded?
      b2b_order_items.find { |item| item.wholesaler_post_id.present? }&.wholesaler_post_id
    else
      b2b_order_items.where.not(wholesaler_post_id: nil).pick(:wholesaler_post_id)
    end
  end

  def accepted?
    request_status == "accepted_request" && status == "pending_payment"
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def pending_request?
    request_status == "pending_request" && (status == "pending_request" || status == "pending_payment")
  end

  def accepted_request?
    request_status == "accepted_request"
  end

  def rejected_request?
    request_status == "rejected_request"
  end

  def pending_payment?
    status == "pending_payment"
  end

  def request_record?
    request_status.present?
  end

  def final_order?
    %w[paid confirmed shipped delivered replacement_requested replacement_approved replacement_shipped replacement_delivered cancelled].include?(status)
  end

  def paid?
    status == "paid"
  end

  def confirmed?
    status == "confirmed"
  end

  def shipped?
    status == "shipped"
  end

  def delivered?
    status == "delivered"
  end

  def payment_completed?
    payment_status == "paid"
  end

  def can_transition_to?(next_status)
    allowed = {
      "confirmed" => %w[shipped cancelled],
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

  def mark_shipped!(note: nil)
    raise StandardError, "Only confirmed orders can be shipped" unless confirmed?
    
    update!(
      status: "shipped",
      status_note: note.presence || status_note,
      shipped_at: shipped_at || Time.current
    )
  end

  def mark_delivered!(note: nil)
    raise StandardError, "Only shipped orders can be delivered" unless shipped?
    
    update!(
      status: "delivered",
      status_note: note.presence || status_note,
      delivered_at: delivered_at || Time.current
    )
  end

  def can_accept?
    pending_request? && expires_at.present? && Time.current < expires_at
  end

  def mark_accepted!(dealer)
    raise "Order already accepted" if accepted_at.present?
    
    update!(
      seller_dealer_id: dealer.id,
      request_status: "accepted_request",
      status: "pending_payment",
      accepted_at: Time.current
    )
  end

  def mark_rejected!
    update!(
      request_status: "rejected_request",
      status: "cancelled",
      rejected_at: Time.current
    )
  end

  def mark_payment_paid!
    raise StandardError, "Only pending payment orders can be marked as paid" unless pending_payment?
    
    update!(
      status: "paid",
      payment_status: "paid",
      payment_confirmed_at: Time.current
    )
  end

  def mark_order_confirmed!
    update!(
      status: "confirmed",
      confirmed_at: Time.current
    )
  end

  def expire!
    return unless pending_request?

    update!(
      request_status: "expired_request",
      status: "cancelled",
      expired_at: Time.current
    )

    dealer_broadcast_trackers.pending.update_all(status: "expired")

    b2b_order_offers.open_state.update_all(
      status: "expired",
      responded_at: Time.current
    )
  end

  def expire_pending_payment!
    return unless pending_payment?

    update!(
      request_status: "expired_request",
      status: "cancelled",
      payment_status: "failed",
      expired_at: Time.current
    )
  end

  def release_reserved_inventory!
    b2b_order_items.accepted_items.find_each do |item|
      if item.wholesaler_post_id.present?
        wholesaler_post = WholesalerPost.lock.find_by(id: item.wholesaler_post_id)
        wholesaler_post&.update!(stock_quantity: wholesaler_post.stock_quantity.to_i + item.quantity.to_i)
      elsif item.dealer_product_id.present?
        dealer_product = DealerProduct.lock.find_by(id: item.dealer_product_id)
        dealer_product&.update!(stock_quantity: dealer_product.stock_quantity.to_i + item.quantity.to_i)
      end
    end
  end

  def recalculate_totals!
    priced_items = b2b_order_items.accepted_items.includes(product_variant: :product)

    subtotal = 0.to_d
    tax = 0.to_d

    priced_items.each do |item|
      pricing = Pricing::PriceCalculator.new(
        variant: item.product_variant,
        quantity: item.quantity,
        user_type: :dealer
      ).call

      subtotal += pricing[:subtotal]
      tax += pricing[:gst_amount]
    end

    self.subtotal_amount = subtotal
    self.tax_amount = tax
    self.total_amount = subtotal - discount_amount.to_d
    save!
  end

  def replacement_window_open?
    return false if delivered_at.blank?

    Time.current <= delivered_at + 48.hours
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

  def assign_payment_token
    self.payment_token ||= SecureRandom.hex(32)
  end

  def set_reference_number
    self.reference_number = generate_reference_number
  end
  
  def generate_reference_number
    date_prefix = Time.current.strftime("%m%y")
    
    self.class.transaction do
      last_order = self.class.where("reference_number LIKE ?", "SPINB2B#{date_prefix}%")
                             .or(self.class.where("reference_number LIKE ?", "SPINB2B#{date_prefix}%"))
                             .order(reference_number: :desc)
                             .lock
                             .first
      
      serial = if last_order.present?
                 last_num = last_order.reference_number.split("-").last.to_i
                 last_num.positive? ? last_num + 1 : (last_order.reference_number[-4..-1].to_i + 1)
               else
                 1
               end
      
      "SPINB2B#{date_prefix}#{serial.to_s.rjust(4, '0')}"
    end
  end
end
