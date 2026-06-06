class AddJoiningFieldsToAdminUsers < ActiveRecord::Migration[8.0]
  def change
    change_table :admin_users, bulk: true do |t|
      t.string :alternate_phone
      t.text :address
      t.string :aadhar_number
      t.string :pan_number
      t.string :bank_name
      t.string :bank_account_number
      t.string :ifsc_code
      t.string :account_holder_name
      t.string :tenth_school_name
      t.string :tenth_board
      t.string :tenth_passing_year
      t.string :tenth_percentage
      t.string :twelfth_school_name
      t.string :twelfth_board
      t.string :twelfth_passing_year
      t.string :twelfth_percentage
    end
  end
end
