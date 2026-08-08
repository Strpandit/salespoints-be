class AddAdHocColorToItems < ActiveRecord::Migration[8.0]
  def change
    add_column :order_items, :ad_hoc_color, :string
    add_column :b2b_order_items, :ad_hoc_color, :string
  end
end
