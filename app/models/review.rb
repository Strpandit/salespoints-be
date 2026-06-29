class Review < ApplicationRecord
  belongs_to :account
  belongs_to :dealer_product, optional: true
  belongs_to :product, optional: true

  validates :title, presence: true, length: { maximum: 50 }
  validates :comment, presence: true, length: { minimum: 5 }
  validates :rating, presence: true, inclusion: { in: 1..5 }

  validates :account_id, uniqueness: { 
    scope: :product_id, 
    message: "can only review each product once",
    if: -> { product_id.present? }
  }

  scope :product_reviews, -> { where.not(product_id: nil) }
  scope :dealer_reviews, -> { where.not(dealer_product_id: nil) }

  before_save :check_for_spam

  def check_for_spam
    if comment&.downcase&.include?("spam")
      errors.add(:comment, "contains inappropriate content")
      throw(:abort)
    end
  end

  def hide!
    update(hidden: true)
  end

  def restore!
    update(hidden: false)
  end

  def formatted_date
    created_at.strftime("%B %d, %Y")
  end

  def product_name
    product&.name || dealer_product&.product&.name || "Product"
  end
  
  def review_type
    product.present? ? "B2C" : "B2B"
  end
end
