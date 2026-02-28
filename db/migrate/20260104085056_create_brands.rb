class CreateBrands < ActiveRecord::Migration[8.0]
  def change
    create_table :brands do |t|
      t.string :name
      t.string :slug
      t.boolean :is_active

      t.timestamps
    end
  end
end
