module Api
  class DealerPayoutsController < ApplicationController
    def index
      payouts = apply_filters(scoped_payouts).recent.page(params[:page]).per(params[:per_page] || 20)

      summary_meta = {}
      if current_dealer.present?
        summary_meta = DealerPayoutService.new(dealer: current_dealer).summary_balances
      end

      render json: {
        data: DealerPayoutSerializer.render(payouts),
        meta: {
          current_page: payouts.current_page,
          next_page: payouts.next_page,
          prev_page: payouts.prev_page,
          total_pages: payouts.total_pages,
          total_count: payouts.total_count
        }.merge(summary_meta),
        message: "Dealer payouts fetched successfully"
      }, status: :ok
    end

    def summary
      unless current_dealer.present? || current_admin.present?
        return render json: { error: "Unauthorized" }, status: :forbidden
      end

      target_dealer =
        if current_dealer.present?
          current_dealer
        elsif params[:dealer_id].present?
          Dealer.find_by(id: params[:dealer_id])
        end

      return render json: { error: "Dealer not found" }, status: :not_found unless target_dealer

      data = DealerPayoutService.new(dealer: target_dealer).summary_balances

      render json: {
        data: data,
        message: "Payout summary fetched successfully"
      }, status: :ok
    end

    def eligible_orders
      return render json: { error: "Dealer only" }, status: :forbidden unless current_dealer.present?

      data = DealerPayoutService.new(dealer: current_dealer).eligible_orders

      render json: {
        data: data,
        message: "Eligible payout orders fetched successfully"
      }, status: :ok
    end

    def create
      return render json: { error: "Dealer only" }, status: :forbidden unless current_dealer.present?

      payout = DealerPayoutService.new(dealer: current_dealer).request!(
        amount: params[:amount],
        note: params[:note],
        order_id: params[:order_id],
        order_type: params[:order_type],
        orders: params[:orders],
        invoice_number: params[:invoice_number],
        gst_invoice: params[:gst_invoice]
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

    def apply_filters(scope)
      if params[:status].present? && params[:status] != "all"
        scope = scope.where(status: params[:status])
      end

      if params[:search].present?
        query = "%#{params[:search].to_s.strip}%"
        scope = scope.joins("LEFT JOIN dealers ON dealers.id = dealer_payouts.dealer_id")
                     .where(
                       "dealer_payouts.request_number ILIKE :q OR " \
                       "dealer_payouts.payment_reference ILIKE :q OR " \
                       "dealers.first_name ILIKE :q OR " \
                       "dealers.last_name ILIKE :q OR " \
                       "dealers.dealer_code ILIKE :q",
                       q: query
                     )
      end

      if params[:start_date].present?
        scope = scope.where("dealer_payouts.created_at >= ?", Time.zone.parse(params[:start_date]).beginning_of_day)
      end

      if params[:end_date].present?
        scope = scope.where("dealer_payouts.created_at <= ?", Time.zone.parse(params[:end_date]).end_of_day)
      end

      scope
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
        if params[:disburse_via_cashfree].to_s == "true"
          payout = SettlementAndPayoutAutomationService.new.process_cashfree_payout!(
            payout: payout,
            admin: current_admin
          )
        else
          service.mark_processing!(payout: payout, admin: current_admin, note: params[:admin_note])
        end
      when "paid"
        service.mark_paid!(
          payout: payout,
          admin: current_admin,
          payment_reference: params[:payment_reference].to_s,
          payment_mode: params[:payment_mode].to_s.presence || "bank_transfer",
          note: params[:admin_note],
          penalty: params[:penalty]
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
