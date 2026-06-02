module Api
  class DealerLedgerEntriesController < ApplicationController
    def index
      dealer = resolve_dealer_scope
      return render json: { error: "Dealer not found" }, status: :not_found unless dealer

      entries = dealer.dealer_ledger_entries.includes(:order, :return_request).recent.page(params[:page]).per(params[:per_page] || 20)

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

    def resolve_dealer_scope
      return Dealer.find_by(id: params[:dealer_id]) if current_admin.present? && params[:dealer_id].present?
      return current_dealer if current_dealer.present?
      return Dealer.find_by(id: params[:dealer_id]) if current_admin.present?

      nil
    end
  end
end
