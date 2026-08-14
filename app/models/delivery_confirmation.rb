class DeliveryConfirmation < ApplicationRecord
  belongs_to :deliverable, polymorphic: true
  belongs_to :seller_dealer, class_name: "Dealer", optional: true
  belongs_to :buyer, polymorphic: true
  belongs_to :return_request, optional: true

  has_one_attached :product_with_customer_image
  has_one_attached :product_packaging_image
  has_many_attached :product_open_box_images

  STATUSES = %w[pending_form pending_otp completed expired].freeze
  CONTEXTS = %w[original replacement].freeze

  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :context, inclusion: { in: CONTEXTS }
  validates :deliverable_type, inclusion: { in: %w[Order B2bOrder] }

  before_validation :ensure_token, on: :create
  before_validation :ensure_context, on: :create
  before_validation :sync_participants_from_deliverable, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :original_context, -> { where(context: "original") }
  scope :replacement_context, -> { where(context: "replacement") }

  def completed?
    status == "completed"
  end

  def pending_otp?
    status == "pending_otp"
  end

  def buyer_verified?
    buyer_otp_verified_at.present?
  end

  def invoice_reference_time
    deliverable.try(:shipped_at) || submitted_at || created_at
  end

  def buyer_otp_valid?(otp)
    buyer_otp.present? && buyer_otp.to_s.strip == otp.to_s.strip && buyer_otp_sent_at.present? && buyer_otp_sent_at > 10.minutes.ago
  end

  def seller_name
    seller_dealer&.dealer_code.presence || seller_dealer&.full_name
  end

  def buyer_name
    if buyer.respond_to?(:dealer_code)
      buyer.dealer_code
    elsif buyer.respond_to?(:full_name)
      buyer.full_name
    else
      buyer_type
    end
  end

  private

  def ensure_token
    self.token ||= SecureRandom.hex(24)
  end

  def ensure_context
    self.context ||= "original"
  end

  def sync_participants_from_deliverable
    return if deliverable.blank?

    self.seller_dealer ||= extract_seller
    self.buyer ||= extract_buyer
    self.seller_phone ||= phone_for(seller_dealer)
    self.buyer_phone ||= phone_for(buyer)
  end

  def extract_seller
    case deliverable
    when Order
      deliverable.seller_dealer
    when B2bOrder
      deliverable.seller_dealer
    end
  end

  def extract_buyer
    case deliverable
    when Order
      deliverable.buyer
    when B2bOrder
      deliverable.buyer_dealer
    end
  end

  def phone_for(record)
    return nil if record.blank? || record.phone.blank?

    cc = record.try(:country_code).presence || "+91"
    "#{cc}#{record.phone}".gsub(/\s+/, "")
  end
end
