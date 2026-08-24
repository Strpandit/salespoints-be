class DealerLedgerEntrySerializer < ApplicationSerializer
  attributes :entry_type, :direction, :amount, :balance_after, :reference_code, :description,
             :metadata, :created_at, :order_number, :order_id, :return_request_id,
             :payout_id, :payout_request_number, :dealer_payout

  def amount
    object.amount.to_f
  end

  def balance_after
    object.balance_after.to_f
  end

  def order_id
    object.order_id || (object.metadata.is_a?(Hash) ? object.metadata["order_id"] : nil)
  end

  def order_number
    if object.order.present?
      object.order.order_number
    elsif object.metadata.is_a?(Hash)
      ref = object.metadata["order_reference"] || object.metadata["reference_number"]
      return ref if ref.present?

      if object.metadata["requestable_type"] == "B2bOrder" && object.metadata["requestable_id"].present?
        b2b = B2bOrder.find_by(id: object.metadata["requestable_id"])
        return b2b.reference_number if b2b.present?
      end

      if object.metadata["requestable_type"] == "Order" && object.metadata["requestable_id"].present?
        ord = Order.find_by(id: object.metadata["requestable_id"])
        return ord.order_number if ord.present?
      end

      nil
    end
  end

  def payout_id
    if object.metadata.is_a?(Hash)
      object.metadata["payout_id"] || object.metadata["dealer_payout_id"]
    end
  end

  def payout_request_number
    if object.metadata.is_a?(Hash)
      object.metadata["payout_request_number"] || object.metadata["request_number"]
    end
  end

  def dealer_payout
    p_id = payout_id
    return nil unless p_id.present?
    payout = DealerPayout.find_by(id: p_id)
    return nil unless payout.present?
    DealerPayoutSerializer.render_one(payout)
  rescue StandardError
    nil
  end
end
