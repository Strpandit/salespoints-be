class CreateTicketMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :ticket_messages do |t|
      t.references :support_ticket, foreign_key: true, null: false
      t.references :account, foreign_key: true, null: true
      t.references :admin_user, foreign_key: true, null: true
      t.string :sender_type, null: false  # 'customer', 'dealer', 'admin', 'system'
      t.text :message, null: false
      t.integer :attachments_count, default: 0
      t.boolean :is_internal, default: false  # Admin-only messages
      t.timestamps
    end

    # add_index :ticket_messages, :support_ticket_id
    add_index :ticket_messages, :created_at
  end
end
