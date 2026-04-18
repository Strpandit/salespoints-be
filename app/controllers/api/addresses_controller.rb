module Api
  class AddressesController < ApplicationController
    before_action :authenticate_request!
    before_action :set_account
    before_action :set_address, only: [:show, :update, :destroy]

    def index
      return render json: { error: 'Not authorized' }, status: :unauthorized unless current_account
      render json: serialize_resource(current_account.addresses, AddressSerializer), status: :ok
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

    def set_account
      @account = current_account
      return render json: { error: 'Not authorized' }, status: :unauthorized unless @account
    end

    def set_address
      @address = current_account.addresses.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { errors: "Address not found", status: 404 }, status: :not_found
    end

    def address_params
      params.require(:address).permit(:name, :address_line1, :address_line2, :city, :state, :country, :postal_code, :phone, :address_type, :is_default)
    end
  end
end
