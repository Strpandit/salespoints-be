class CreateReportAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :report_audit_logs do |t|
      t.string :user_type, null: false
      t.bigint :user_id, null: false
      t.string :report_key, null: false
      t.string :format, null: false
      t.jsonb :applied_filters, default: {}, null: false
      t.integer :row_count, default: 0
      t.string :ip_address
      t.string :user_agent
      t.datetime :downloaded_at, null: false
      t.timestamps
    end

    add_index :report_audit_logs, [:user_type, :user_id]
    add_index :report_audit_logs, :report_key
    add_index :report_audit_logs, :created_at
  end
end
