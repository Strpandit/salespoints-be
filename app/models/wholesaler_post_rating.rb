class WholesalerPostRating < ApplicationRecord
  belongs_to :wholesaler_post
  belongs_to :dealer

  validates :rating, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }
end
