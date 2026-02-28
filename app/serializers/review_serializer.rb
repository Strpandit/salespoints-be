class ReviewSerializer < ActiveModel::Serializer
  attributes :id, :title, :comment, :rating, :verified, :author, :date

  def author
    object.account&.full_name || "Unknown"
  end

  def date
    object.created_at.strftime("%B %d, %Y")
  end
end
