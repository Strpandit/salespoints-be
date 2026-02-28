class CreateDealers < ActiveRecord::Migration[8.0]
  def change
    create_table :dealers do |t|
      t.string :first_name
      t.string :last_name
      t.string :email, index: { unique: true }
      t.string :phone, index: { unique: true }
      t.string :status, default: 'pending'
      t.string :password_digest
      t.string :otp_pin
      t.datetime :otp_sent_at
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :deleted_at
      t.string :gender
      t.string :country_code, default: '+91'

      t.timestamps
    end
  end
end
