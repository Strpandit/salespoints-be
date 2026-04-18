class CatFilterSerializer < ApplicationSerializer
  attributes :name, :data_type, :is_filterable, :category_id

  belongs_to :category
end
