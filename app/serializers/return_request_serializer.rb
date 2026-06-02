class ReturnRequestSerializer < ApplicationSerializer
  attributes :request_type, :status, :reason, :details, :refund_amount, :seller_adjustment_amount,
             :resolution_notes, :approved_at, :received_at, :completed_at, :rejected_at, :cancelled_at,
             :created_at, :updated_at, :requester_name

  def refund_amount
    object.refund_amount.to_f
  end

  def seller_adjustment_amount
    object.seller_adjustment_amount.to_f
  end

  def requester_name
    if object.requester.respond_to?(:full_name)
      object.requester.full_name
    else
      object.requester.try(:first_name).presence || object.requester.try(:email) || object.requester_type
    end
  end
end
