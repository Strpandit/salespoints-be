class DealerPayoutSerializer < ApplicationSerializer
  attributes :request_number, :amount, :status, :bank_name, :bank_account_number, :ifsc_code,
             :account_holder_name, :payment_reference, :payment_mode, :admin_note,
             :approved_at, :processing_at, :paid_at, :rejected_at, :cancelled_at,
             :created_at, :updated_at, :dealer_name, :dealer_code

  def amount
    object.amount.to_f
  end

  def dealer_name
    object.dealer&.full_name
  end

  def dealer_code
    object.dealer&.dealer_code
  end
end
