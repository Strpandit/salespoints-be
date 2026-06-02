class Dealer < ApplicationRecord
  has_secure_password validations: false

  has_one :dealer_profile, dependent: :destroy, inverse_of: :dealer
  has_one :dealer_location, dependent: :destroy, inverse_of: :dealer
  has_many :dealer_products
  has_many :coupons, foreign_key: :created_by_dealer_id, dependent: :nullify
  has_many :buyer_b2b_orders, class_name: "B2bOrder", foreign_key: :buyer_dealer_id, dependent: :destroy
  has_many :seller_b2b_orders, class_name: "B2bOrder", foreign_key: :seller_dealer_id, dependent: :nullify
  has_many :b2b_order_offers, dependent: :destroy
  has_many :notifications, as: :receiver, dependent: :destroy
  has_many :dealer_deletion_requests, dependent: :destroy
  has_many :push_subscriptions, as: :subscriber, dependent: :destroy
  has_many :products, through: :dealer_products
  has_many :wholesaler_posts, dependent: :destroy
  has_many :wholesaler_post_ratings, dependent: :destroy
  has_one :cart, as: :buyer, dependent: :destroy
  has_many :orders, as: :buyer, dependent: :destroy
  has_many :payment_attempts, as: :buyer, dependent: :destroy
  has_many :sales_orders, class_name: "Order", foreign_key: :seller_dealer_id, dependent: :nullify
  has_many :order_items, through: :sales_orders
  has_many :dealer_ledger_entries, dependent: :destroy
  has_many :dealer_payouts, dependent: :destroy
  has_many :support_tickets, foreign_key: "dealer_id", dependent: :destroy
  has_many :ticket_messages, foreign_key: "dealer_id", dependent: :destroy

  accepts_nested_attributes_for :dealer_profile, reject_if: :all_blank
  accepts_nested_attributes_for :dealer_location, reject_if: :all_blank

  enum :status, { pending: 'pending', active: 'active', inactive: 'inactive', banned: 'banned', rejected: 'rejected' }

  before_validation :normalize_phone
  before_validation :normalize_email
  before_validation :generate_dealer_code, on: :create
  # before_validation :generate_password, on: :create

  scope :active, -> { where(status: "active") }

  validates :email,
    allow_blank: true,
    uniqueness: { case_sensitive: false },
    format: {
      with: /\A[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@
            [a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}\z/x
    }
  validates :phone, uniqueness: true, allow_blank: true
  validates :dealer_code,
    uniqueness: true,
    allow_nil: true,
    format: { with: /\ASPIN\d{4,}\z/, message: "must follow SPIN0001 format" }

  after_create :create_default_cart

  def full_name
    [first_name, last_name].compact.join(" ")
  end

  def otp_valid?(otp)
    otp_pin == otp && otp_sent_at.present? && otp_sent_at > 5.minutes.ago
  end

  def clear_otp!
    update!(otp_pin: nil, otp_sent_at: nil)
  end

  private

  # def generate_password
  #   return if password.present?

  #   year = Time.current.year.to_s
  #   email_part = email.to_s.split('@').first.to_s[0, 3]
  #   email_part = email_part.ljust(3, "x")
  #   generated_password = "#{email_part}@#{year}"
  #   self.password = generated_password
  #   self.password_confirmation = generated_password
  # end

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

  def create_default_cart
    create_cart unless cart
  end

  def generate_dealer_code
    return if dealer_code.present?

    last_code = Dealer.where("dealer_code LIKE ?", "SPIN%")
                      .order(Arel.sql("LENGTH(dealer_code) DESC"), dealer_code: :desc)
                      .pick(:dealer_code)

    last_number = last_code.to_s.delete_prefix("SPIN").to_i
    self.dealer_code = format("SPIN%04d", last_number + 1)
  end
end
