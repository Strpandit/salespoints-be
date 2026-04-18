class CreateB2bOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :b2b_orders do |t|
      t.references :buyer_dealer, null: false, foreign_key: { to_table: :dealers }
      t.references :seller_dealer, foreign_key: { to_table: :dealers }
      t.string :status, null: false, default: "pending"
      t.decimal :subtotal_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :tax_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :discount_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_amount, precision: 12, scale: 2, null: false, default: 0
      t.string :coupon_code
      t.integer :requested_radius_km, null: false, default: 5
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.datetime :accepted_at
      t.datetime :cancelled_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :b2b_orders, :status
  end
end
