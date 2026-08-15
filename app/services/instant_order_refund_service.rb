class InstantOrderRefundService
  class << self
    def process_refund!(order:, reason: "Order request rejected or unaccepted by sellers")
      return false if order.blank?

      return false unless order.payment_status.to_s.downcase == "paid"
      return false if order.payment_method.to_s.downcase == "cod"
      return false if order.respond_to?(:refund_status) && order.refund_status.to_s.downcase == "processed"

      order_reference =
        if order.is_a?(Order)
          order.gateway_order_reference.presence || order.payment_reference.presence || order.order_number
        elsif order.is_a?(B2bOrder)
          order.payment_session_id.presence || order.payment_token.presence || order.reference_number
        else
          order.try(:order_number) || order.try(:reference_number) || order.id.to_s
        end

      return false if order_reference.blank?

      refund_id = "REFUND-#{order.class.name.first(3).upcase}-#{order.id}-#{Time.current.to_i}"
      refund_amount = order.total_amount.to_d.round(2)

      return false unless refund_amount.positive?

      begin
        CashfreeService.new.create_refund(
          order_reference: order_reference,
          refund_id: refund_id,
          amount: refund_amount,
          note: reason
        )
      rescue StandardError => e
        Rails.logger.error("[InstantOrderRefundService] Cashfree API refund error for Order #{order_reference}: #{e.message}")
        order.update!(
          status_note: [order.try(:status_note), "Instant refund attempt via Cashfree failed: #{e.message}"].compact.join(" | ")
        ) rescue nil
        return false
      end

      Order.transaction do
        if order.is_a?(Order)
          order.update!(
            payment_status: "refunded",
            refund_status: "processed",
            refund_amount: refund_amount,
            refunded_at: Time.current,
            refund_reason: reason,
            status_note: [order.status_note, "Instant refund of ₹#{refund_amount} processed via Cashfree (Refund ID: #{refund_id})"].compact.join(" | ")
          )
        elsif order.is_a?(B2bOrder)
          order.update!(
            payment_status: "refunded",
            status_note: [order.status_note, "Instant refund of ₹#{refund_amount} processed via Cashfree (Refund ID: #{refund_id})"].compact.join(" | ")
          )
        end
      end

      if order.is_a?(Order)
        EmailDispatcherService.retail_order_terminated(order, "Order rejected by all sellers. ₹#{refund_amount} refunded to your payment account via Cashfree.") rescue nil
      elsif order.is_a?(B2bOrder)
        EmailDispatcherService.b2b_order_terminated(order, "Order request rejected by seller. ₹#{refund_amount} refunded to your payment account via Cashfree.") rescue nil
      end

      true
    end
  end
end
