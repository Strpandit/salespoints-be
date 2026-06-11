class DealerSerializer < ApplicationSerializer

  attributes :first_name, :last_name, :email, :phone, :gender, :country_code, :status, :dealer_code, :full_name, :created_at, :updated_at,
             :pending_deletion_request, :settlement_balance, :otp_verified

  has_one :dealer_profile
  has_one :dealer_location

  def pending_deletion_request
    object.deletion_requests.pending.exists?
  end

  def settlement_balance
    object.settlement_balance.to_f
  end

  def otp_verified
    object.otp_pin.blank?
  end
end
