class AddSignupTokenToDealersAndAdminUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :dealers, :signup_token, :string
    add_column :dealers, :signup_token_sent_at, :datetime
    add_index :dealers, :signup_token, unique: true

    add_column :admin_users, :signup_token, :string
    add_column :admin_users, :signup_token_sent_at, :datetime
    add_index :admin_users, :signup_token, unique: true
  end
end
