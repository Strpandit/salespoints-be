class ReturnRequestTransitionService
  def initialize(return_request:, actor:, resolution_notes: nil, refund_amount: nil)
    @return_request = return_request
    @actor = actor
    @resolution_notes = resolution_notes
    @refund_amount = refund_amount.present? ? BigDecimal(refund_amount.to_s).round(2) : nil
  end

  def transition!(next_status:)
    next_status = next_status.to_s
    raise StandardError, "Invalid return request status" unless ReturnRequest::STATUSES.include?(next_status)
    raise StandardError, "Invalid return request transition" unless allowed_statuses.include?(next_status)

    ReturnRequest.transaction do
      request = ReturnRequest.lock.includes(order: [:order_items, :seller_dealer]).find(@return_request.id)
      attrs = {
        status: next_status,
        resolution_notes: @resolution_notes.presence || request.resolution_notes
      }

      case next_status
      when "approved"
        attrs[:approved_at] = request.approved_at || Time.current
        reserve_replacement_inventory!(request) if request.replacement_request?
      when "received"
        attrs[:received_at] = request.received_at || Time.current
      when "completed"
        attrs[:completed_at] = request.completed_at || Time.current
      when "rejected"
        attrs[:rejected_at] = request.rejected_at || Time.current
      when "cancelled"
        attrs[:cancelled_at] = request.cancelled_at || Time.current
      end

      request.update!(attrs.compact)
      sync_order_status!(request)
      complete_return_actions!(request) if next_status == "completed"
      request
    end
  end

  private

  def allowed_statuses
    {
      "requested" => %w[approved rejected cancelled],
      "approved" => %w[in_transit cancelled],
      "in_transit" => %w[received completed cancelled],
      "received" => %w[completed],
      "completed" => [],
      "rejected" => [],
      "cancelled" => []
    }.fetch(@return_request.status.to_s, [])
  end

  def sync_order_status!(request)
    order_status =
      case [request.request_type, request.status]
      when ["return", "requested"] then "return_requested"
      when ["return", "approved"] then "return_approved"
      when ["return", "in_transit"] then "return_in_transit"
      when ["return", "received"], ["return", "completed"] then "returned"
      when ["replacement", "requested"] then "replacement_requested"
      when ["replacement", "approved"] then "replacement_approved"
      when ["replacement", "in_transit"] then "replacement_shipped"
      when ["replacement", "received"], ["replacement", "completed"] then "replacement_delivered"
      else
        "delivered"
      end

    request.order.update!(status: order_status, status_note: @resolution_notes.presence || request.order.status_note)
  end

  def complete_return_actions!(request)
    if request.return_request?
      restock_original_inventory!(request.order)
      OrderRefundService.new(
        order: request.order,
        actor: @actor,
        amount: @refund_amount || request.order.refundable_amount_remaining,
        reason: @resolution_notes.presence || request.reason.presence || "Return completed",
        return_request: request
      ).call
    end
  end

  def reserve_replacement_inventory!(request)
    request.order.order_items.includes(:dealer_product).find_each do |item|
      dealer_product = DealerProduct.lock.find(item.dealer_product_id)
      raise StandardError, "Insufficient stock for replacement" if dealer_product.stock_quantity.to_i < item.quantity.to_i

      dealer_product.update!(stock_quantity: dealer_product.stock_quantity.to_i - item.quantity.to_i)
    end
  end

  def restock_original_inventory!(order)
    order.order_items.includes(:dealer_product).find_each do |item|
      dealer_product = DealerProduct.lock.find(item.dealer_product_id)
      dealer_product.update!(stock_quantity: dealer_product.stock_quantity.to_i + item.quantity.to_i)
    end
  end
end
