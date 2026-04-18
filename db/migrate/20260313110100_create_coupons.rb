class CreateCoupons < ActiveRecord::Migration[8.0]
  def change
    create_table :coupons do |t|
      t.string :code, null: false
      t.string :title
      t.text :description
      t.references :created_by_dealer, foreign_key: { to_table: :dealers }
      t.string :audience, null: false, default: "customer"
      t.string :discount_type, null: false, default: "percentage"
      t.decimal :discount_value, precision: 10, scale: 2, null: false, default: 0
      t.decimal :max_discount, precision: 10, scale: 2
      t.decimal :min_cart_amount, precision: 10, scale: 2, null: false, default: 0
      t.integer :max_uses
      t.integer :used_count, null: false, default: 0
      t.integer :per_user_limit, null: false, default: 1
      t.datetime :starts_at
      t.datetime :expires_at
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    add_index :coupons, :code, unique: true
    add_index :coupons, :audience
  end
end
