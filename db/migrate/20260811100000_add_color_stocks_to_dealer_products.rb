class AddColorStocksToDealerProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :dealer_products, :color_stocks, :jsonb, default: {}, null: false
  end
end
