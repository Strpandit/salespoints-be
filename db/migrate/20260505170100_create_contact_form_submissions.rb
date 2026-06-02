class CreateContactFormSubmissions < ActiveRecord::Migration[7.0]
  def change
    create_table :contact_form_submissions do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :phone, null: true
      t.string :subject, null: false
      t.text :message, null: false
      t.string :status, default: 'received'  # 'received', 'read', 'responded'
      t.text :admin_response, null: true
      t.references :admin_user, foreign_key: true, null: true
      t.datetime :responded_at, null: true
      t.timestamps
    end

    add_index :contact_form_submissions, :email
    add_index :contact_form_submissions, :status
  end
end
