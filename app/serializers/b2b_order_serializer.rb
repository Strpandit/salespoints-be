class B2bOrderSerializer < ApplicationSerializer
  attributes :status, :coupon_code, :requested_radius_km, :accepted_at, :cancelled_at,
             :expires_at, :created_at, :buyer_dealer_id, :seller_dealer_id,
             :subtotal_amount, :tax_amount, :discount_amount, :total_amount,
             :buyer_name, :seller_name, :open_items_count, :accepted_items_count, :latitude, :longitude,
             :payment_method, :payment_status

  has_many :b2b_order_items

  def subtotal_amount
    object.subtotal_amount.to_f
  end

  def tax_amount
    object.tax_amount.to_f
  end

  def discount_amount
    object.discount_amount.to_f
  end

  def total_amount
    object.total_amount.to_f
  end

  def buyer_name
    object.buyer_dealer&.dealer_code
  end

  def seller_name
    object.seller_dealer&.dealer_code
  end

  def open_items_count
    object.b2b_order_items.count { |item| item.status == "open" }
  end

  def accepted_items_count
    object.b2b_order_items.count { |item| item.status == "accepted" }
  end
end
