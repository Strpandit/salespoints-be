class AddSalesChannelsToDealerProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :dealer_products, :sell_in_b2b, :boolean, default: true, null: false
    add_column :dealer_products, :sell_in_b2c, :boolean, default: true, null: false
  end
end
