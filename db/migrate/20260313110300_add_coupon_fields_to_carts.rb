class AddCouponFieldsToCarts < ActiveRecord::Migration[8.0]
  def change
    add_reference :carts, :coupon, foreign_key: true
    add_column :carts, :coupon_code, :string
  end
end
