class DealerProfileSerializer < ApplicationSerializer
  attributes :business_name, :business_type, :gst_number, :pan_number,
             :aadhar_number, :bank_name, :bank_account_number, :ifsc_code,
             :business_address, :business_contact_number, :business_email,
             :is_verified, :created_at, :updated_at
end
