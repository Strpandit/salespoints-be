class CartSerializer < ApplicationSerializer
  attributes :total_items, :total_amount, :taxable_amount, :subtotal_amount, :tax_amount, :coupon_discount_amount,
             :grand_total, :applied_coupon
  has_many :cart_items

  def total_amount
    object.total_amount.to_f
  end

  def subtotal_amount
    object.subtotal_amount.to_f
  end

  def taxable_amount
    object.taxable_amount.to_f
  end
  
  def tax_amount
    object.tax_amount.to_f
  end

  def coupon_discount_amount
    object.coupon_discount_amount.to_f
  end

  def grand_total
    object.grand_total.to_f
  end

  def applied_coupon
    return nil unless object.coupon.present?

    {
      id: object.coupon.id,
      code: object.coupon.code,
      title: object.coupon.title,
      audience: object.coupon.audience,
      discount_type: object.coupon.discount_type,
      discount_value: object.coupon.discount_value.to_f,
      max_discount: object.coupon.max_discount&.to_f,
      min_cart_amount: object.coupon.min_cart_amount.to_f,
      max_uses: object.coupon.max_uses,
      used_count: object.coupon.used_count,
      remaining_uses: object.coupon.max_uses.present? ? [object.coupon.max_uses - object.coupon.used_count, 0].max : nil,
      per_user_limit: object.coupon.per_user_limit,
      expires_at: object.coupon.expires_at
    }
  end
end
