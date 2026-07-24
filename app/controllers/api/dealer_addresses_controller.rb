module Api
  class DealerAddressesController < ApplicationController
    before_action :require_dealer!
    before_action :set_address, only: [:show, :update, :destroy]

    def index
      addresses = current_dealer.dealer_addresses.order(is_default: :desc, created_at: :desc)
      render json: serialize_resource(addresses, AddressSerializer).merge(
        message: "Dealer addresses fetched successfully"
      ), status: :ok
    end

    def create
      address = current_dealer.dealer_addresses.new(address_params)
      current_dealer.dealer_addresses.update_all(is_default: false) if truthy?(address_params[:is_default])

      if address.save
        render json: serialize_resource(address, AddressSerializer).merge(
          message: "Address added successfully"
        ), status: :created
      else
        render json: { errors: address.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def show
      render json: serialize_resource(@address, AddressSerializer).merge(
        message: "Address fetched successfully"
      ), status: :ok
    end

    def update
      current_dealer.dealer_addresses.update_all(is_default: false) if truthy?(address_params[:is_default])

      if @address.update(address_params)
        render json: serialize_resource(@address, AddressSerializer).merge(
          message: "Address updated successfully"
        ), status: :ok
      else
        render json: { errors: @address.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @address.destroy
      render json: { message: "Address deleted successfully" }, status: :ok
    end

    private

    def require_dealer!
      return if current_dealer.present?

      render json: { error: "Dealer only" }, status: :unauthorized
    end

    def set_address
      @address = current_dealer.dealer_addresses.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Address not found" }, status: :not_found
    end

    def address_params
      params.require(:address).permit(
        :name, :address_line1, :address_line2, :city, :state, :country,
        :postal_code, :phone, :address_type, :is_default, :latitude, :longitude
      )
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
