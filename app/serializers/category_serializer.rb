class CategorySerializer < ApplicationSerializer
  attributes :name, :slug, :is_active

  has_many :cat_filters
end
