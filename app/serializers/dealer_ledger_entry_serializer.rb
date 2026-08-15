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
end
