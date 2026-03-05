class CreateWholesalerPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :wholesaler_posts do |t|
      t.references :dealer, null: false, foreign_key: { to_table: :dealers }
      t.references :dealer_product, foreign_key: true
      t.string :title
      t.text :body
      t.decimal :price, precision: 12, scale: 2
      t.integer :stock_quantity, default: 0
      t.string :modal_no
      
      t.timestamps
    end
  end
end
