class CreateCatFilters < ActiveRecord::Migration[8.0]
  def change
    create_table :cat_filters do |t|
      t.string :name
      t.string :data_type
      t.boolean :is_filterable, default: true
      t.references :category, foreign_key: true

      t.timestamps
    end
  end
end
