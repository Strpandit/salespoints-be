class CreateReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :reviews do |t|
      t.references :account, null: false, foreign_key: true
      t.references :dealer_product, null: false, foreign_key: true
      t.string :title
      t.text :comment
      t.integer :rating
      t.boolean :verified

      t.timestamps
    end
  end
end
