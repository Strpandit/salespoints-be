class ReviewSerializer < ApplicationSerializer
  attributes :title, :comment, :rating, :verified

  def author
    object.account&.full_name || "Unknown"
  end

  def date
    object.created_at.strftime("%B %d, %Y")
  end
end
