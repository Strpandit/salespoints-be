class AddressSerializer < ApplicationSerializer
  attributes :name, :address_line1, :address_line2, :city, :state, :country, :postal_code, :phone, :address_type, :is_default
end
