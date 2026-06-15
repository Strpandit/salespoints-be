class BrandCategory < ApplicationRecord
  belongs_to :brand
  belongs_to :category

  validates :brand_id, uniqueness: { scope: :category_id }
end
