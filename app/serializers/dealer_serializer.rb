class DealerSerializer < ApplicationSerializer

  attributes :first_name, :last_name, :email, :phone, :gender, :country_code, :status, :dealer_code, :full_name, :created_at, :updated_at,
             :pending_deletion_request

  has_one :dealer_profile
  has_one :dealer_location

  def pending_deletion_request
    object.dealer_deletion_requests.pending.exists?
  end
end
