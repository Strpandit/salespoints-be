class CatFilter < ApplicationRecord
  belongs_to :category

  DATA_TYPES = %w[string number boolean select].freeze

  validates :name, presence: true
  validates :data_type, inclusion: { in: DATA_TYPES }
end
