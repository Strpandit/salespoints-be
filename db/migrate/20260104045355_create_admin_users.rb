class CreateAdminUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_users do |t|
      t.string :first_name
      t.string :last_name
      t.string :email, index: { unique: true }
      t.string :phone, index: { unique: true }
      t.string :country_code, default: '+91'
      t.string :status, default: 'active'
      t.string :password_digest
      t.string :otp_pin
      t.datetime :otp_sent_at
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :deleted_at
      t.datetime :last_login_at
      t.boolean :is_super_admin, default: false

      t.timestamps
    end

    add_index  :admin_users, :is_super_admin
  end
end
