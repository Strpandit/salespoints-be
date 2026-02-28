class BrandSerializer < ActiveModel::Serializer
  attributes :id, :name, :slug, :is_active
end