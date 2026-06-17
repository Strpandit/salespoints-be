class AddPincodes < ActiveRecord::Migration[8.0]
  def change
    add_column :admin_users, :pincodes, :string, array: true, default: []
    add_column :wholesaler_posts, :pincodes, :string, array: true, default: []
    add_column :dealers, :pincode, :string
    add_index :admin_users, :pincodes, using: 'gin'
    add_index :wholesaler_posts, :pincodes, using: 'gin'
    add_index :dealers, :pincode

    # price in products

    add_column :products, :price, :decimal, precision: 15, scale: 2
    add_column :products, :selling_price, :decimal, precision: 15, scale: 2
    add_column :products, :dealer_price, :decimal, precision: 15, scale: 2
    add_column :products, :dealer_selling_price, :decimal, precision: 15, scale: 2
    add_column :products, :discount_percentage, :integer, default: 0
  end
end
