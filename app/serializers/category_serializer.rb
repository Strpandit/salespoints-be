class CategorySerializer < ActiveModel::Serializer
  attributes :id, :name, :slug, :is_active

  has_many :cat_filters
end
