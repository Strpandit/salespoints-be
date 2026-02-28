class CreateDealerProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :dealer_profiles do |t|
      t.references :dealer, null: false, foreign_key: true
      t.string :business_name
      t.string :business_type
      t.string :gst_number
      t.string :pan_number
      t.string :aadhar_number
      t.string :bank_name
      t.string :bank_account_number
      t.string :ifsc_code
      t.text :business_address
      t.string :business_contact_number
      t.string :business_email
      t.boolean :is_verified, default: false

      t.timestamps
    end
  end
end
