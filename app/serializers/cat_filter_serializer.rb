class CatFilterSerializer < ActiveModel::Serializer
  attributes :id, :name, :data_type, :is_filterable, :category_id

  belongs_to :category, serializer: CategorySerializer
end
