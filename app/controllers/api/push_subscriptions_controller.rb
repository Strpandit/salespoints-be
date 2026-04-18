module Api
  class PushSubscriptionsController < ApplicationController
    def create
      token = params[:token].to_s.strip
      platform = params[:platform].to_s.strip.presence

      return render json: { error: "token is required" }, status: :unprocessable_entity if token.blank?

      sub = PushSubscription.find_or_initialize_by(token: token)
      sub.subscriber = current_user
      sub.platform = platform
      sub.save!

      render json: { message: "Registered" }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
