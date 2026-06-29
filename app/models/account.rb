class Account < ApplicationRecord
  has_secure_password validations: false
  acts_as_paranoid

  has_many :addresses, dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_many :orders, as: :buyer, dependent: :destroy
  has_many :payment_attempts, as: :buyer, dependent: :destroy
  has_many :notifications, as: :receiver, dependent: :destroy
  has_many :deletion_requests, as: :requestable, dependent: :destroy
  has_many :push_subscriptions, as: :subscriber, dependent: :destroy
  has_many :support_tickets, foreign_key: "account_id", dependent: :destroy
  has_many :ticket_messages, foreign_key: "account_id", dependent: :destroy

  enum :status, { pending: 'pending', active: 'active', inactive: 'inactive', banned: 'banned' }
  enum :gender, { male: 'male', female: 'female', prefer_not_to_say: 'prefer_not_to_say' }

  before_validation :normalize_phone
  before_validation :normalize_email
  scope :active, -> { where(status: "active") }

  validates :email,
    allow_blank: true,
    uniqueness: { case_sensitive: false },
    format: {
      with: /\A[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@
            [a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}\z/x
    }
  validates :phone, uniqueness: true, allow_blank: true

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
    mobile = phone.to_s.gsub(/\D/, '').sub(/^0+/, '')
    self.phone = mobile.presence
    if country_code.present?
      self.country_code = "+#{country_code.gsub(/\D/, '')}"
    end
  end

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

end
