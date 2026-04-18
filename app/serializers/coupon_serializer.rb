class CouponSerializer < ApplicationSerializer
  attributes :code, :title, :description, :audience, :discount_type,
             :max_uses, :used_count, :per_user_limit, :starts_at, :expires_at,
             :is_active, :created_at

  def discount_value
    object.discount_value.to_f
  end

  def max_discount
    object.max_discount&.to_f
  end

  def min_cart_amount
    object.min_cart_amount.to_f
  end

  def remaining_uses
    return nil if object.max_uses.blank?

    [object.max_uses - object.used_count.to_i, 0].max
  end
end
