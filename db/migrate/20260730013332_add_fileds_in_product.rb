class AddFiledsInProduct < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :hsn_code, :string
    add_column :product_variants, :hsn_code, :string
    add_column :wholesaler_posts, :hsn_code, :string
    add_column :orders, :invoice_number, :string
    add_column :b2b_orders, :invoice_number, :string
    add_column :b2b_orders, :tracking_id, :string
    add_column :return_requests, :shipped_at, :datetime

    remove_reference :return_requests, :order, foreign_key: true
    add_reference :return_requests, :requestable, polymorphic: true, null: false

    add_index :orders, :invoice_number, unique: true
    add_index :b2b_orders, :invoice_number, unique: true
    add_index :b2b_orders, :tracking_id, unique: true
  end
end
