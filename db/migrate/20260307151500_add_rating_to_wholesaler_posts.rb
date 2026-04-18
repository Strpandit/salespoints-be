class AddRatingToWholesalerPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :wholesaler_posts, :rating, :decimal, precision: 3, scale: 2, default: 0.0, null: false
    add_column :wholesaler_posts, :rating_count, :integer, default: 0, null: false
  end
end
