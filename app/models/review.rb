class Review < ApplicationRecord
  belongs_to :account
  belongs_to :dealer_product

  validates :title, presence: true, length: { maximum: 50 }
  validates :comment, presence: true, length: { minimum: 5 }
  validates :rating, presence: true, inclusion: { in: 1..5 }

  validates :account_id, uniqueness: { scope: :dealer_product_id, message: "can only review each product once" }

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
end
