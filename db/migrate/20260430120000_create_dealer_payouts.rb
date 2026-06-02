class CreateDealerPayouts < ActiveRecord::Migration[8.0]
  def change
    create_table :dealer_payouts do |t|
      t.references :dealer, null: false, foreign_key: true
      t.string :request_number, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.string :bank_name
      t.string :bank_account_number
      t.string :ifsc_code
      t.string :account_holder_name
      t.string :payment_reference
      t.string :payment_mode
      t.text :admin_note
      t.datetime :approved_at
      t.datetime :processing_at
      t.datetime :paid_at
      t.datetime :rejected_at
      t.datetime :cancelled_at
      t.bigint :approved_by_admin_id
      t.bigint :processed_by_admin_id
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :dealer_payouts, :request_number, unique: true
    add_index :dealer_payouts, :status
    add_index :dealer_payouts, :approved_by_admin_id
    add_index :dealer_payouts, :processed_by_admin_id
    add_foreign_key :dealer_payouts, :admin_users, column: :approved_by_admin_id
    add_foreign_key :dealer_payouts, :admin_users, column: :processed_by_admin_id
  end
end
