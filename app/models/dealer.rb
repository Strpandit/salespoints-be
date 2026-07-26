class Dealer < ApplicationRecord
  has_secure_password validations: false
  acts_as_paranoid

  has_one :dealer_profile, dependent: :destroy, inverse_of: :dealer
  has_one :dealer_location, dependent: :destroy, inverse_of: :dealer
  has_many :addresses, dependent: :destroy
  has_many :dealer_products, dependent: :nullify
  has_many :coupons, foreign_key: :created_by_dealer_id, dependent: :nullify
  has_many :buyer_b2b_orders, class_name: "B2bOrder", foreign_key: :buyer_dealer_id, dependent: :destroy
  has_many :seller_b2b_orders, class_name: "B2bOrder", foreign_key: :seller_dealer_id, dependent: :nullify
  has_many :b2b_order_offers, dependent: :destroy
  has_many :notifications, as: :receiver, dependent: :destroy
  has_many :deletion_requests, as: :requestable, dependent: :destroy
  has_many :push_subscriptions, as: :subscriber, dependent: :destroy
  has_many :products, through: :dealer_products
  has_many :wholesaler_posts, dependent: :destroy
  has_many :wholesaler_post_ratings, dependent: :destroy
  has_many :orders, as: :buyer, dependent: :destroy
  has_many :payment_attempts, as: :buyer, dependent: :destroy
  has_many :sales_orders, class_name: "Order", foreign_key: :seller_dealer_id, dependent: :nullify
  has_many :order_items, through: :sales_orders
  has_many :dealer_ledger_entries, dependent: :destroy
  has_many :dealer_payouts, dependent: :destroy
  has_many :support_tickets, foreign_key: "dealer_id", dependent: :destroy
  has_many :ticket_messages, foreign_key: "dealer_id", dependent: :destroy
  has_many :dealer_broadcast_trackers, dependent: :destroy
  belongs_to :deleted_by, class_name: "AdminUser", optional: true

  has_many :order_broadcast_trackers, dependent: :destroy
  has_many :order_offers, dependent: :destroy
  has_many :sales_orders, class_name: "Order", foreign_key: :seller_dealer_id, dependent: :nullify
  has_many :purchase_orders, class_name: 'Order', as: :buyer

  accepts_nested_attributes_for :dealer_profile, reject_if: :all_blank
  accepts_nested_attributes_for :dealer_location, reject_if: :all_blank

  enum :status, { pending: 'pending', active: 'active', inactive: 'inactive', banned: 'banned', rejected: 'rejected' }

  before_validation :normalize_phone
  before_validation :normalize_email
  before_validation :generate_dealer_code, on: :create
  before_destroy :deactivate_associated_records, prepend: true
  # before_validation :generate_password, on: :create

  scope :active, -> { where(status: "active") }

  validates :email,
    allow_blank: true,
    uniqueness: { case_sensitive: false, conditions: -> { where(deleted_at: nil) } },
    format: {
      with: /\A[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@
            [a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}\z/x
    }
  validates :phone, uniqueness: { conditions: -> { where(deleted_at: nil) } }, allow_blank: true
  validates :dealer_code,
    uniqueness: { conditions: -> { where(deleted_at: nil) } },
    allow_nil: true,
    format: { with: /\ASPIN\d{4,}\z/, message: "must follow SPIN0001 format" }

  validates :pincode, presence: true,
                      format: { with: /\A[1-9][0-9]{5}\z/, message: "must be valid 6-digit pincode" },
                      allow_blank: true

  def full_name
    [first_name, last_name].compact.join(" ")
  end

  def otp_valid?(otp)
    otp_pin == otp && otp_sent_at.present? && otp_sent_at > 5.minutes.ago
  end

  def clear_otp!
    update!(otp_pin: nil, otp_sent_at: nil)
  end

  def orders
    sales_orders
  end

  def update_location_from_address!
    return false if dealer_profile.blank? || dealer_profile.business_address.blank?

    service = GoogleMapsService.instance
    result = service.geocode(dealer_profile.business_address)
    return false if result.blank?

    if dealer_location.present?
      dealer_location.update!(
        latitude: result[:latitude],
        longitude: result[:longitude]
      )
    else
      create_dealer_location!(
        latitude: result[:latitude],
        longitude: result[:longitude],
        service_radius_km: 5,
        is_active: true
      )
    end
    true
  end

  def driving_distance_from(lat, lng)
    return nil if dealer_location.blank?
    return nil if dealer_location.latitude.blank? || dealer_location.longitude.blank?

    dealer_location.driving_distance_to(lat, lng)
  end

  def serves_location?(lat, lng)
    return false if dealer_location.blank?
    dealer_location.serves_location?(lat, lng)
  end

  def self.nearby(lat, lng, radius_km: 10, limit: 20)
    DealerLocation.nearby_dealers(lat, lng, radius_km: radius_km, limit: limit)
  end
  private

  def normalize_phone
    mobile = phone.to_s.gsub(/\D/, '').sub(/^0+/, '')
    self.phone = mobile.presence
    if country_code.present?
      self.country_code = "+#{country_code.gsub(/\D/, '')}"
    end
  end

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def generate_dealer_code
    return if dealer_code.present?

    last_code = Dealer.where("dealer_code LIKE ?", "SPIN%")
                      .where(deleted_at: nil)
                      .order(Arel.sql("LENGTH(dealer_code) DESC"), dealer_code: :desc)
                      .pick(:dealer_code)

    last_number = last_code.to_s.delete_prefix("SPIN").to_i
    self.dealer_code = format("SPIN%04d", last_number + 1)
  end

  def deactivate_associated_records
    dealer_products.update_all(
      is_active: false,
      approve_status: 'inactive'
    )
    
    wholesaler_posts.update_all(
      is_active: false,
      approve_status: 'rejected'
    )
  end
end
