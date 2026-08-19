class AddMfYearToWholesalerPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :wholesaler_posts, :mf_year, :string
  end
end
