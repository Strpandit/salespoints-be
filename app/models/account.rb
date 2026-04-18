class Account < ApplicationRecord
  has_secure_password validations: false
  acts_as_paranoid

  has_many :addresses, dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_one  :cart, as: :buyer, dependent: :destroy
  has_many :cart_items, through: :cart
  has_many :orders, as: :buyer, dependent: :destroy
  has_many :payment_attempts, as: :buyer, dependent: :destroy
  has_many :notifications, as: :receiver, dependent: :destroy
  has_many :account_deletion_requests, dependent: :destroy
  has_many :push_subscriptions, as: :subscriber, dependent: :destroy

  enum :status, { pending: 'pending', active: 'active', inactive: 'inactive', banned: 'banned' }
  enum :gender, { male: 'male', female: 'female', other: 'other' }

  before_validation :normalize_phone
  scope :active, -> { where(status: "active") }

  validates :email, uniqueness: { case_sensitive: false }, allow_nil: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :phone, uniqueness: true, allow_nil: true

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

  def normalize_phone
    return if phone.blank?
    self.phone = phone.gsub(/\D/, '').sub(/^0+/, '')
    if country_code.present?
      self.country_code = "+#{country_code.gsub(/\D/, '')}"
    end
  end

  def create_default_cart
    create_cart unless cart.present?
  end

end
