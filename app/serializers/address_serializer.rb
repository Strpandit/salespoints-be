class AddressSerializer < ApplicationSerializer
  attributes :name, :address_line1, :address_line2, :city, :state, :country, :postal_code, :phone, :address_type, :is_default, :latitude, :longitude, :owner_type

  def owner_type
    return "Account" if object.account_id.present?
    return "Dealer" if object.dealer_id.present?

    nil
  end
end
