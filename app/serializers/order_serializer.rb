class OrderSerializer < ApplicationSerializer
  attributes :order_number, :status, :created_at, :placed_at, :coupon_code,
             :payment_method, :payment_status, :billing_address, :shipping_address,
             :status_display, :total_items, :items_count, :subtotal, :subtotal_amount,
             :tax_amount, :shipping_amount, :discount_amount, :total_amount,
             :customer_name, :customer_email, :buyer_name, :seller_name

  has_many :order_items

  def status_display
    object.status.to_s.humanize
  end

  def total_items
    object.total_items
  end

  def items_count
    object.total_items
  end

  def subtotal
    object.subtotal_amount.to_f
  end

  def subtotal_amount
    object.subtotal_amount.to_f
  end

  def tax_amount
    object.tax_amount.to_f
  end

  def shipping_amount
    0.0
  end

  def discount_amount
    object.discount_amount.to_f
  end

  def total_amount
    object.total_amount.to_f
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

  def customer_email
    object.buyer&.email
  end

  def buyer_name
    if object.buyer.respond_to?(:full_name)
      object.buyer.full_name
    elsif object.buyer.respond_to?(:first_name)
      object.buyer.first_name
    else
      "Customer"
    end
  end

  def seller_name
    object.seller_dealer&.full_name || object.seller_dealer&.dealer_code
  end
end
