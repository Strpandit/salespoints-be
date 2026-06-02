class DealerLedgerEntrySerializer < ApplicationSerializer
  attributes :entry_type, :direction, :amount, :balance_after, :reference_code, :description,
             :metadata, :created_at, :order_number, :return_request_id

  def amount
    object.amount.to_f
  end

  def balance_after
    object.balance_after.to_f
  end

  def order_number
    object.order&.order_number
  end
end
