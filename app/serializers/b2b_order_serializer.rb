class B2bOrderSerializer < ApplicationSerializer
  attributes :reference_number, :status, :coupon_code, :requested_radius_km, :accepted_at, :cancelled_at,
             :expires_at, :created_at, :buyer_dealer_id, :seller_dealer_id,
             :subtotal_amount, :taxable_amount, :tax_amount, :discount_amount, :total_amount,
             :buyer_name, :seller_name, :open_items_count, :accepted_items_count, :latitude, :longitude,
             :payment_method, :payment_status, :request_status, :source_type, :is_direct_buy,
             :payment_link_sent_at, :confirmed_at, :payment_confirmed_at, :shipped_at, :delivered_at,
             :status_note

  has_many :b2b_order_items
  has_one :delivery_confirmation

  def subtotal_amount
    object.subtotal_amount.to_f
  end

  def taxable_amount
    object.subtotal_amount.to_d - object.tax_amount.to_d
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
