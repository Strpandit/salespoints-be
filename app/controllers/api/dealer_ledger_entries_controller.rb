module Api
  class DealerLedgerEntriesController < ApplicationController
    def index
      dealer = resolve_dealer_scope
      return render json: { error: "Dealer not found" }, status: :not_found unless dealer

      DealerPayoutService.new(dealer: dealer).summary_balances rescue nil

      scope = dealer.dealer_ledger_entries.includes(:order, :return_request)
      scope = apply_ledger_filters(scope)
      entries = scope.recent.page(params[:page]).per(params[:per_page] || 20)

      render json: {
        data: DealerLedgerEntrySerializer.render(entries),
        meta: {
          current_page: entries.current_page,
          next_page: entries.next_page,
          prev_page: entries.prev_page,
          total_pages: entries.total_pages,
          total_count: entries.total_count,
          settlement_balance: dealer.settlement_balance.to_f
        },
        message: "Dealer ledger fetched successfully"
      }, status: :ok
    end

    private

    def apply_ledger_filters(scope)
      if params[:entry_type].present? && params[:entry_type] != "all"
        scope = scope.where(entry_type: params[:entry_type])
      end

      if params[:direction].present? && params[:direction] != "all"
        scope = scope.where(direction: params[:direction])
      end

      if params[:start_date].present?
        scope = scope.where("created_at >= ?", Time.zone.parse(params[:start_date].to_s).beginning_of_day)
      end

      if params[:end_date].present?
        scope = scope.where("created_at <= ?", Time.zone.parse(params[:end_date].to_s).end_of_day)
      end

      if params[:search].present?
        q = "%#{params[:search].to_s.strip}%"
        scope = scope.where("reference_code ILIKE :q OR description ILIKE :q", q: q)
      end

      scope
    end

    def resolve_dealer_scope
      return Dealer.find_by(id: params[:dealer_id]) if current_admin.present? && params[:dealer_id].present?
      return current_dealer if current_dealer.present?
      return Dealer.find_by(id: params[:dealer_id]) if current_admin.present?

      nil
    end
  end
end
