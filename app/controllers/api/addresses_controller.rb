module Api
  class AddressesController < ApplicationController
    before_action :set_account
    before_action :authenticate_request!, except: [:index, :show]
    before_action :authorize_account!, only: [:create, :update, :destroy]
    before_action :set_address, only: [:show, :update, :destroy]

    def index
      render json: current_account.addresses, each_serializer: AddressSerializer
    end

    def create
      address = current_account.addresses.new(address_params)
      if address.is_default
        current_account.addresses.update_all(is_default: false)
      end
      if address.save
        render json: {
          data: AddressSerializer.new(address),
          message: "Address added successfully"
        }, status: :created
      else
        render json: {
          errors: address.errors.full_messages,
        }, status: :unprocessable_entity
      end
    end

    def show
      render json: {
        data: AddressSerializer.new(@address),
        message: "Address details fetched successfully"
      }, status: :ok
    end

    def update
      if address_params[:is_default] == true || address_params[:is_default] == "true"
        current_account.addresses.update_all(is_default: false)
      end
      if @address.update(address_params)
        render json: {
          data: AddressSerializer.new(@address),
          message: "Address updated successfully"
        }, status: :ok
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
      @account = Account.find(params[:account_id])
    rescue ActiveRecord::RecordNotFound
      render json: { errors: "Account not found", status: 404 }, status: :not_found
    end

    def authorize_account!
      unless current_account && current_account.id == @account.id
        render json: { error: 'Not authorized' }, status: :forbidden
      end
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
