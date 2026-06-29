class AddSourceToB2bOrdersAndItems < ActiveRecord::Migration[8.0]
  def change
    add_column :b2b_orders, :source_type, :string
    add_column :b2b_orders, :source_id, :integer
    add_column :b2b_orders, :is_direct_buy, :boolean, default: false
    add_column :b2b_orders, :request_status, :string, default: "pending_request"
    add_column :b2b_orders, :requested_at, :datetime
    add_column :b2b_orders, :payment_link_sent_at, :datetime
    add_column :b2b_orders, :rejected_at, :datetime
    add_column :b2b_orders, :expired_at, :datetime
    add_column :b2b_orders, :payment_confirmed_at, :datetime
    add_column :b2b_orders, :confirmed_at, :datetime
    
    add_column :b2b_order_items, :wholesaler_post_id, :integer

    add_column :reviews, :product_id, :bigint
    change_column_null :reviews, :dealer_product_id, true
    
    add_index :b2b_orders, [:source_type, :source_id]
    add_index :b2b_orders, :is_direct_buy
    add_index :b2b_orders, :request_status
    add_index :b2b_orders, [:request_status, :expires_at]
    add_index :b2b_order_items, :wholesaler_post_id
    add_index :reviews, :product_id
    
    add_foreign_key :reviews, :products, column: :product_id
    add_foreign_key :b2b_order_items, :wholesaler_posts, column: :wholesaler_post_id
  end
end
