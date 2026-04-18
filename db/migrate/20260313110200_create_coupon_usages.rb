class CreateCouponUsages < ActiveRecord::Migration[8.0]
  def change
    create_table :coupon_usages do |t|
      t.references :coupon, null: false, foreign_key: true
      t.string :user_type, null: false
      t.bigint :user_id, null: false
      t.integer :uses_count, null: false, default: 0
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :coupon_usages, [:coupon_id, :user_type, :user_id], unique: true, name: "idx_coupon_usages_unique"
  end
end
