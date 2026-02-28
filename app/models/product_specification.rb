class ProductSpecification < ApplicationRecord
  belongs_to :product

  validates :key, :value, presence: true
end
