class AccountSerializer < ActiveModel::Serializer
  attributes :id, :first_name, :last_name, :email, :phone, :status, :gender, :country_code, :google_signup, :created_at
  has_many :addresses
end
