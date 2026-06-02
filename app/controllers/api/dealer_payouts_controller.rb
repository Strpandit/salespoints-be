module Api
  class DealerPayoutsController < ApplicationController
    def index
      payouts = scoped_payouts.recent.page(params[:page]).per(params[:per_page] || 20)

      render json: {
        data: DealerPayoutSerializer.render(payouts),
        meta: {
          current_page: payouts.current_page,
          next_page: payouts.next_page,
          prev_page: payouts.prev_page,
          total_pages: payouts.total_pages,
          total_count: payouts.total_count
        },
        message: "Dealer payouts fetched successfully"
      }, status: :ok
    end

    def create
      return render json: { error: "Dealer only" }, status: :forbidden unless current_dealer.present?

      payout = DealerPayoutService.new(dealer: current_dealer).request!(
        amount: params[:amount],
        note: params[:note]
      )

      render json: {
        data: DealerPayoutSerializer.render(payout),
        message: "Payout request submitted successfully"
      }, status: :created
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def update
      payout = scoped_payouts.find_by(id: params[:id])
      return render json: { error: "Payout request not found" }, status: :not_found unless payout

      if current_admin.present?
        handle_admin_transition!(payout)
      elsif current_dealer.present?
        handle_dealer_transition!(payout)
      else
        return render json: { error: "Unauthorized" }, status: :forbidden
      end

      render json: {
        data: DealerPayoutSerializer.render(payout.reload),
        message: "Payout request updated successfully"
      }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def scoped_payouts
      if current_admin.present?
        DealerPayout.includes(:dealer, :approved_by_admin, :processed_by_admin)
      elsif current_dealer.present?
        current_dealer.dealer_payouts.includes(:approved_by_admin, :processed_by_admin)
      else
        DealerPayout.none
      end
    end

    def handle_admin_transition!(payout)
      service = DealerPayoutService.new(dealer: payout.dealer)
      action = params[:action_type].to_s

      case action
      when "approve"
        service.approve!(payout: payout, admin: current_admin, note: params[:admin_note])
      when "reject"
        service.reject!(payout: payout, admin: current_admin, note: params[:admin_note])
      when "processing"
        service.mark_processing!(payout: payout, admin: current_admin, note: params[:admin_note])
      when "paid"
        service.mark_paid!(
          payout: payout,
          admin: current_admin,
          payment_reference: params[:payment_reference].to_s,
          payment_mode: params[:payment_mode].to_s,
          note: params[:admin_note]
        )
      when "failed"
        service.mark_failed!(payout: payout, admin: current_admin, note: params[:admin_note])
      else
        raise StandardError, "Invalid admin payout action"
      end
    end

    def handle_dealer_transition!(payout)
      raise StandardError, "Unauthorized payout request access" unless payout.dealer_id == current_dealer.id

      action = params[:action_type].to_s
      if action == "cancel"
        DealerPayoutService.new(dealer: current_dealer).cancel!(payout: payout)
      else
        raise StandardError, "Invalid dealer payout action"
      end
    end
  end
end
