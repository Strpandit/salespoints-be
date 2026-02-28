class DealerSerializer < ActiveModel::Serializer
  attributes :id, :first_name, :last_name, :email, :phone, :gender, :country_code, :status

  has_one :dealer_profile
  has_one :dealer_location
end
