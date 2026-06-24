class OrderSerializer < ApplicationSerializer
  attributes :order_number, :status, :created_at, :placed_at, :coupon_code,
             :payment_method, :payment_status, :billing_address, :shipping_address,
             :status_display, :total_items, :items_count, :subtotal, :subtotal_amount,
             :tax_amount, :shipping_amount, :discount_amount, :total_amount,
             :customer_name, :customer_email, :buyer_name, :seller_name,
             :commission_rate, :commission_amount, :marketplace_fee_amount,
             :seller_settlement_amount, :settlement_status, :settlement_due_at,
             :settled_at, :hold_released_at, :refund_status, :refund_amount,
             :refunded_at, :refund_reason, :return_window_closes_at, :payment_reference,
             :status_note

  has_many :order_items
  has_many :return_requests

  def items_count
    object.order_items.sum(:quantity)
  end

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

  def shipping_amount
    0
  end

  def total_amount
    object.total_amount.to_f
  end

  def commission_rate
    object.commission_rate.to_f
  end

  def commission_amount
    object.commission_amount.to_f
  end

  def marketplace_fee_amount
    object.marketplace_fee_amount.to_f
  end

  def seller_settlement_amount
    object.seller_settlement_amount.to_f
  end

  def refund_amount
    object.refund_amount.to_f
  end

  def total_items
    object.total_items
  end

  def subtotal
    object.subtotal_amount.to_f
  end

  def customer_name
    if object.buyer.respond_to?(:full_name)
      object.buyer.full_name
    elsif object.buyer.respond_to?(:first_name)
      object.buyer.first_name
    else
      "Customer"
    end
  end

  def buyer_name
    buyer = object.buyer

    if buyer.respond_to?(:dealer_code)
      buyer.dealer_code
    elsif buyer.respond_to?(:full_name)
      buyer.full_name
    else
      buyer&.first_name
    end
  end

  def customer_email
    object.buyer&.email
  end

  def seller_name
    object.seller_dealer&.dealer_code || object.seller_dealer&.full_name
  end

  def status_display
    object.status.titleize
  end
end
