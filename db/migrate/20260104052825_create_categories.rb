class CreateCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :categories do |t|
      t.string :name
      t.string :slug
      t.boolean :is_active, default: true

      t.timestamps
    end
  end
end
