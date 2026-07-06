class AddReuploadedAtToWholesalerPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :wholesaler_posts, :reuploaded_at, :datetime
  end
end
