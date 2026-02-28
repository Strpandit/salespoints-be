class Dealer < ApplicationRecord
  has_secure_password validations: false

  has_one :dealer_profile, dependent: :destroy, inverse_of: :dealer
  has_one :dealer_location, dependent: :destroy, inverse_of: :dealer
  has_many :dealer_products
  has_many :products, through: :dealer_products
  has_one :cart, as: :buyer, dependent: :destroy
  # has_many :orders, as: :buyer
  # has_many :order_items, through: :orders

  accepts_nested_attributes_for :dealer_profile, reject_if: :all_blank
  accepts_nested_attributes_for :dealer_location, reject_if: :all_blank

  enum :status, { pending: 'pending', active: 'active', inactive: 'inactive', banned: 'banned', rejected: 'rejected' }

  before_validation :normalize_phone
  before_validation :generate_password, on: :create

  scope :active, -> { where(status: "active") }

  validates :email, uniqueness: { case_sensitive: false }, allow_nil: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :phone, uniqueness: true, allow_nil: true

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

  def generate_password
    return if password.present?

    year = Time.current.year.to_s
    email_part = email.to_s.split('@').first.to_s[0, 3]
    email_part = email_part.ljust(3, "x")
    generated_password = "#{email_part}@#{year}"
    self.password = generated_password
    self.password_confirmation = generated_password
  end

  def normalize_phone
    return if phone.blank?
    self.phone = phone.gsub(/\D/, '')
    if country_code.present?
      code = country_code.gsub(/\D/, '')
      self.phone = phone.sub(/^0+/, '')
      self.phone = "#{code}#{self.phone}" unless self.phone.start_with?(code)
    end
  end
end
