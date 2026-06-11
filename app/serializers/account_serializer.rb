class AccountSerializer < ApplicationSerializer
  attributes :first_name, :last_name, :email, :phone, :status, :gender, :country_code, :google_signup, :created_at,
             :pending_deletion_request
  has_many :addresses

  def pending_deletion_request
    object.deletion_requests.pending.exists?
  end
end
