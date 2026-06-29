class ReviewSerializer < ApplicationSerializer
  attributes :id, :title, :comment, :rating, :verified, :created_at, :formatted_date, :review_type

  def author
    object.account&.full_name || "Unknown"
  end

  def date
    object.created_at.strftime("%B %d, %Y")
  end

  attributes :reviewable_id do |object|
    object.product_id || object.dealer_product_id
  end

  attributes :reviewable_type do |object|
    if object.product.present?
      "Product"
    elsif object.dealer_product.present?
      "DealerProduct"
    else
      "Unknown"
    end
  end
end
