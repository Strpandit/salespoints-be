module Api
  class AddressesController < ApplicationController
    before_action :authenticate_request!
    before_action :set_address, only: [:show, :update, :destroy]
    before_action :authorize_address!, only: [:show, :update, :destroy]

    def index
      addresses = current_account.addresses.order(is_default: :desc, created_at: :desc)
      render json: serialize_resource(addresses, AddressSerializer), status: :ok
    end

    def create
      address = current_account.addresses.new(address_params)
      if address.is_default
        current_account.addresses.update_all(is_default: false)
      end
      if address.save
        render json: serialize_resource(address, AddressSerializer).merge(
          message: "Address added successfully"
        ), status: :created
      else
        render json: {
          errors: address.errors.full_messages,
        }, status: :unprocessable_entity
      end
    end

    def show
      render json: serialize_resource(@address, AddressSerializer).merge(
        message: "Address details fetched successfully"
      ), status: :ok
    end

    def update
      if address_params[:is_default] == true || address_params[:is_default] == "true"
        current_account.addresses.update_all(is_default: false)
      end
      if @address.update(address_params)
        render json: serialize_resource(@address, AddressSerializer).merge(
          message: "Address updated successfully"
        ), status: :ok
      else
        render json: {
          errors: @address.errors.full_messages,
        }, status: :unprocessable_entity
      end
    end

    def destroy
      @address.destroy
      render json: {
        message: "Address deleted successfully",
      }, status: :ok
    end

    private

    def set_address
      @address = Address.find(params[:id])
    end

    def authorize_address!
      unless @address.account_id == current_account.id
        render json: { error: 'Not authorized' }, status: :forbidden
      end
    end

    def address_params
      params.require(:address).permit(:name, :address_line1, :address_line2, :city, :state, :country, :postal_code, :phone, :address_type, :is_default, :latitude, :longitude)
    end
  end
end
