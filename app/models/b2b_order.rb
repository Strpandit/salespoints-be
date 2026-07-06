class B2bOrder < ApplicationRecord
  belongs_to :buyer_dealer, class_name: "Dealer"
  belongs_to :seller_dealer, class_name: "Dealer", optional: true
  belongs_to :buyer_payment_attempt, class_name: "PaymentAttempt", optional: true
  belongs_to :source, polymorphic: true, optional: true
  has_many :b2b_order_items, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy
  has_many :b2b_order_offers, dependent: :destroy
  has_many :dealer_broadcast_trackers, dependent: :destroy

  REQUEST_STATUSES = %w[pending_request accepted_request rejected_request expired_request].freeze
  ORDER_STATUSES = %w[pending_request pending_payment paid confirmed cancelled].freeze
  PAYMENT_METHODS = %w[cod online].freeze
  PAYMENT_STATUSES = %w[pending paid failed].freeze

  validates :request_status, inclusion: { in: REQUEST_STATUSES }, allow_nil: true
  validates :status, inclusion: { in: ORDER_STATUSES }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :requested_radius_km, numericality: { greater_than: 0 }
  # validates :reference_number, presence: true, uniqueness: true

  scope :pending_requests, -> { where(request_status: "pending_request", status: "pending_request") }
  scope :accepted_requests, -> { where(request_status: "accepted_request") }
  scope :pending_payments, -> { where(status: "pending_payment") }
  scope :from_wholesaler_post, -> { where(source_type: 'WholesalerPost') }
  scope :direct_buy, -> { where(is_direct_buy: true) }

  before_validation :assign_payment_token, on: :create
  before_validation :set_reference_number, on: :create

  def accepted?
    request_status == "accepted_request" && status == "pending_payment"
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def can_accept?
    pending_request? && !expired? && !accepted?
  end

  def pending_request?
    request_status == "pending_request" && status == "pending_request"
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
    request_status.nil?
  end

  def paid?
    status == "paid"
  end

  def confirmed?
    status == "confirmed"
  end

  def can_accept?
    pending_request? && expires_at.present? && Time.current < expires_at
  end

  def mark_accepted!(dealer)
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

  private

  def assign_payment_token
    self.payment_token ||= SecureRandom.hex(32)
  end

  def set_reference_number
    self.reference_number = generate_reference_number
  end
  
  def generate_reference_number
    date_prefix = Time.current.strftime("%d%m%Y")
    
    self.class.transaction do
      last_order = self.class.where("reference_number LIKE ?", "SPINB2B#{date_prefix}%")
                             .order(reference_number: :desc)
                             .lock
                             .first
      
      serial = if last_order.present?
                 last_order.reference_number[-6..-1].to_i + 1
               else
                 1
               end
      
      "SPINB2B#{date_prefix}#{serial.to_s.rjust(6, '0')}"
    end
  end
end
