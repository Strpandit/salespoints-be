class Cart < ApplicationRecord
  belongs_to :buyer, polymorphic: true
  belongs_to :coupon, optional: true
  has_many :cart_items, dependent: :destroy
  # has_many :dealer_products, through: :cart_items

  def total_amount
    cart_items.sum(&:total_price)
  end

  def subtotal_amount
    pricing_summary[:subtotal]
  end

  def tax_amount
    pricing_summary[:gst_amount]
  end

  def taxable_amount
    pricing_summary[:taxable_amount]
  end

  def coupon_discount_amount
    return 0.to_d unless coupon.present?
    return 0.to_d unless coupon.active_now?
    return 0.to_d unless coupon.eligible_for_amount?(subtotal_amount)

    coupon.calculate_discount(subtotal_amount)
  end

  def grand_total
    subtotal_amount - coupon_discount_amount
  end

  def total_items
    cart_items.sum(&:quantity)
  end

  def clear
    cart_items.destroy_all
  end

  def apply_coupon!(coupon_code:, user:)
    normalized = coupon_code.to_s.strip.upcase
    raise StandardError, "Coupon code is required" if normalized.blank?

    selected = Coupon.find_by(code: normalized)
    raise StandardError, "Invalid coupon code" if selected.blank?

    valid, message = selected.validate_for_cart!(cart: self, user: user)
    raise StandardError, message unless valid

    update!(coupon: selected, coupon_code: selected.code)
    selected
  end

  def remove_coupon!
    update!(coupon: nil, coupon_code: nil)
  end

  def revalidate_coupon!(user:)
    return true if coupon.blank?

    valid, = coupon.validate_for_cart!(cart: self, user: user)
    return true if valid

    remove_coupon!
    false
  end

  def dealer?
    buyer_type == "Dealer"
  end

  private

  def pricing_summary
    @pricing_summary ||= begin
      subtotal = 0.to_d
      taxable = 0.to_d
      gst = 0.to_d

      cart_items.includes(product_variant: :product).each do |item|
        pricing = Pricing::PriceCalculator.new(
          variant: item.product_variant,
          quantity: item.quantity,
          user_type: dealer? ? :dealer : :account
        ).call

        subtotal += pricing[:subtotal]
        taxable += pricing[:taxable_amount]
        gst += pricing[:gst_amount]
      end

      {
        subtotal: subtotal.round(2),
        taxable_amount: taxable.round(2),
        gst_amount: gst.round(2)
      }
    end
  end
end
