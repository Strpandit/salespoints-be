require 'csv'
module Api
  class BulkUploadsController < ApplicationController
    # Only admin users should be able to run these bulk imports
    before_action :require_admin

    def create
      file = params[:file]
      type = params[:type]&.to_s&.downcase

      unless file && file.respond_to?(:read)
        return render json: { error: 'CSV file required in `file` param' }, status: :bad_request
      end

      unless %w[brands categories cat_filters roles products].include?(type)
        return render json: { error: 'type param must be one of: brands,categories,cat_filters,roles,products' }, status: :bad_request
      end

      result = BulkUploadService.import(type, file.read)

      render json: result, status: :ok
    rescue => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end
end
