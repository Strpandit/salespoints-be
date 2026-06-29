class Coupon < ApplicationRecord
  belongs_to :created_by_dealer, class_name: "Dealer", optional: true
  has_many :coupon_usages, dependent: :destroy

  AUDIENCES = %w[customer dealer].freeze
  DISCOUNT_TYPES = %w[percentage fixed].freeze

  before_validation :normalize_code

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :audience, inclusion: { in: AUDIENCES }
  validates :discount_type, inclusion: { in: DISCOUNT_TYPES }
  validates :discount_value, numericality: { greater_than: 0 }
  validates :max_discount, numericality: { greater_than: 0 }, allow_nil: true
  validates :min_cart_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :max_uses, numericality: { greater_than: 0 }, allow_nil: true
  validates :per_user_limit, numericality: { greater_than: 0 }

  scope :active, -> { where(is_active: true) }

  def applicable_for_user?(user)
    return false if user.nil?

    if audience == "dealer"
      user.is_a?(Dealer)
    else
      user.is_a?(Account)
    end
  end

  def active_now?
    return false unless is_active
    return false if starts_at.present? && Time.current < starts_at
    return false if expires_at.present? && Time.current > expires_at

    true
  end

  def global_uses_available?
    return true if max_uses.blank?

    used_count.to_i < max_uses.to_i
  end

  def eligible_for_amount?(subtotal)
    subtotal.to_d >= min_cart_amount.to_d
  end

  def usage_for(user)
    coupon_usages.find_by(user_type: user.class.name, user_id: user.id)
  end

  def used_by_user_count(user)
    usage_for(user)&.uses_count.to_i
  end

  def user_can_use?(user)
    used_by_user_count(user) < per_user_limit.to_i
  end

  def calculate_discount(subtotal)
    amount = subtotal.to_d
    return 0.to_d if amount <= 0

    discount =
      if discount_type == "percentage"
        (amount * discount_value.to_d) / 100
      else
        discount_value.to_d
      end

    discount = [discount, max_discount.to_d].min if max_discount.present?
    [discount, amount].min
  end

  def validate_for_cart!(user:)
    return [false, "Coupon is inactive"] unless active_now?
    return [false, "Coupon not valid for this user"] unless applicable_for_user?(user)
    return [false, "Coupon usage limit reached"] unless global_uses_available?
    return [false, "You have already used this coupon"] unless user_can_use?(user)

    [true, nil]
  end

  def consume_for!(user)
    raise ArgumentError, "Invalid user for coupon" unless applicable_for_user?(user)

    with_lock do
      raise StandardError, "Coupon usage limit reached" unless global_uses_available?
      raise StandardError, "You have already used this coupon" unless user_can_use?(user)

      usage = coupon_usages.find_or_initialize_by(user_type: user.class.name, user_id: user.id)
      usage.uses_count = usage.uses_count.to_i + 1
      usage.last_used_at = Time.current
      usage.save!

      increment!(:used_count)
    end
  end

  private

  def normalize_code
    self.code = code.to_s.strip.upcase
  end
end
