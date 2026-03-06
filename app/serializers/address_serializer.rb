class AddressSerializer < ActiveModel::Serializer
  attributes :id, :name, :address_line1, :address_line2, :city, :state, :country, :postal_code, :phone, :address_type, :is_default
end
