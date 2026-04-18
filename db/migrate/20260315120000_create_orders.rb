class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.string :order_number, null: false
      t.string :buyer_type, null: false
      t.bigint :buyer_id, null: false
      t.bigint :seller_dealer_id
      t.string :status, null: false, default: "pending"
      t.decimal :subtotal_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :tax_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :discount_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_amount, precision: 12, scale: 2, null: false, default: 0
      t.string :coupon_code
      t.string :payment_method, null: false, default: "cod"
      t.string :payment_status, null: false, default: "pending"
      t.datetime :placed_at
      t.jsonb :billing_address, null: false, default: {}
      t.jsonb :shipping_address, null: false, default: {}

      t.timestamps
    end

    add_index :orders, :order_number, unique: true
    add_index :orders, [:buyer_type, :buyer_id]
    add_index :orders, :status
    add_foreign_key :orders, :dealers, column: :seller_dealer_id
  end
end

