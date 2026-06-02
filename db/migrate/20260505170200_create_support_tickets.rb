class CreateSupportTickets < ActiveRecord::Migration[7.0]
  def change
    create_table :support_tickets do |t|
      t.string :ticket_number, null: false, unique: true
      t.references :account, foreign_key: true, null: true
      t.references :dealer, foreign_key: true, null: true
      t.references :admin_user, foreign_key: true, null: true
      t.string :user_type, null: false  # 'customer', 'dealer', 'admin'
      t.string :subject, null: false
      t.text :description, null: false
      t.string :category, null: false  # 'order_issue', 'payment', 'product', 'account', 'general', 'other'
      t.string :priority, default: 'medium'  # 'low', 'medium', 'high', 'urgent'
      t.string :status, default: 'open'  # 'open', 'in_progress', 'waiting_customer', 'resolved', 'closed'
      t.references :assigned_to, foreign_key: { to_table: :admin_users }, null: true
      t.datetime :resolved_at, null: true
      t.string :resolution_summary, null: true
      t.integer :messages_count, default: 0
      t.timestamps
    end

    add_index :support_tickets, :ticket_number
    add_index :support_tickets, :status
    add_index :support_tickets, :priority
    add_index :support_tickets, :category
    add_index :support_tickets, :user_type
  end
end
