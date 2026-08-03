class AddBankVerificationFieldsToDealerProfiles < ActiveRecord::Migration[7.1]
  def change
    change_table :dealer_profiles, bulk: true do |t|
      t.string :account_holder_name
      t.string :bank_verification_status, null: false, default: "unverified"
      t.string :bank_verification_reference
      t.datetime :bank_verified_at
      t.string :verified_bank_name
      t.string :verified_name_at_bank
      t.text :last_bank_verification_error
      t.jsonb :bank_verification_payload, null: false, default: {}
    end

    add_index :dealer_profiles, :bank_verification_status
    add_index :dealer_profiles, :bank_verification_reference
  end
end
