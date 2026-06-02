class AddMarketplacePaymentFlow < ActiveRecord::Migration[8.0]
  def change
    add_column :dealers, :settlement_balance, :decimal, precision: 14, scale: 2, null: false, default: 0

    change_table :orders, bulk: true do |t|
      t.decimal :commission_rate, precision: 5, scale: 2, null: false, default: 10
      t.decimal :commission_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :marketplace_fee_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :seller_settlement_amount, precision: 12, scale: 2, null: false, default: 0
      t.string :settlement_status, null: false, default: "on_hold"
      t.datetime :settlement_due_at
      t.datetime :settled_at
      t.datetime :hold_released_at
      t.string :refund_status, null: false, default: "none"
      t.decimal :refund_amount, precision: 12, scale: 2, null: false, default: 0
      t.datetime :refunded_at
      t.text :refund_reason
      t.datetime :return_window_closes_at
    end

    add_index :orders, :settlement_status
    add_index :orders, :refund_status
    add_index :orders, :settlement_due_at

    create_table :dealer_ledger_entries do |t|
      t.references :dealer, null: false, foreign_key: true
      t.references :order, null: true, foreign_key: true
      t.bigint :return_request_id
      t.string :entry_type, null: false
      t.string :direction, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :balance_after, precision: 14, scale: 2, null: false, default: 0
      t.string :reference_code
      t.text :description
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :dealer_ledger_entries, :entry_type
    add_index :dealer_ledger_entries, :reference_code, unique: true
    add_index :dealer_ledger_entries, :return_request_id

    create_table :return_requests do |t|
      t.references :order, null: false, foreign_key: true
      t.references :requester, polymorphic: true, null: false
      t.string :request_type, null: false
      t.string :status, null: false, default: "requested"
      t.text :reason
      t.text :details
      t.decimal :refund_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :seller_adjustment_amount, precision: 12, scale: 2, null: false, default: 0
      t.text :resolution_notes
      t.datetime :approved_at
      t.datetime :received_at
      t.datetime :completed_at
      t.datetime :rejected_at
      t.datetime :cancelled_at
      t.timestamps
    end

    add_index :return_requests, :request_type
    add_index :return_requests, :status

    add_foreign_key :dealer_ledger_entries, :return_requests
  end
end
