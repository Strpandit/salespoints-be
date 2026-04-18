class CreateWholesalerPostRatings < ActiveRecord::Migration[8.0]
  def change
    create_table :wholesaler_post_ratings do |t|
      t.references :wholesaler_post, null: false, foreign_key: true
      t.references :dealer, null: false, foreign_key: true
      t.decimal :rating, precision: 3, scale: 2, null: false

      t.timestamps
    end

    add_index :wholesaler_post_ratings, [:wholesaler_post_id, :dealer_id], unique: true, name: "idx_wholesaler_post_ratings_unique"
  end
end
