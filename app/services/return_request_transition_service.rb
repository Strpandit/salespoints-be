class ReturnRequestTransitionService
  def initialize(return_request:, actor:, resolution_notes: nil)
    @return_request = return_request
    @actor = actor
    @resolution_notes = resolution_notes
  end

  def transition!(next_status:)
    effective_actor = @actor || @return_request&.requestable&.try(:seller_dealer) || @return_request&.requester
    raise StandardError, "Unauthorized" if effective_actor.blank?
    next_status = next_status.to_s
    raise StandardError, "Invalid return request status" unless ReturnRequest::STATUSES.include?(next_status)
    raise StandardError, "Invalid return request transition" unless allowed_statuses.include?(next_status)

    ReturnRequest.transaction do
      request = ReturnRequest.lock.find(@return_request.id)
      requestable = request.requestable

      raise StandardError, "Replacement request not found" unless requestable
      raise StandardError, "Only replacement requests are supported" unless request.replacement_request?

      attrs = {
        status: next_status,
        resolution_notes: @resolution_notes.presence || request.resolution_notes
      }

      case next_status
      when "approved"
        attrs[:approved_at] = request.approved_at || Time.current
      when "in_transit"
        attrs[:shipped_at] = request.shipped_at || Time.current
        reserve_replacement_inventory!(request)
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
      sync_order_status!(request, next_status)
      request
    end
  end

  private

  def allowed_statuses
    {
      "requested" => %w[approved rejected cancelled],
      "partially_replacement_requested" => %w[approved rejected cancelled],
      "approved"  => %w[in_transit cancelled],
      "in_transit" => %w[received cancelled],
      "received"   => %w[completed],
      "completed"  => [],
      "rejected"   => [],
      "cancelled"  => []
    }.fetch(@return_request.status.to_s, [])
  end

  def sync_order_status!(request, next_status)
    requestable = request.requestable

    order_status =
      case next_status
      when "requested"
        "replacement_requested"
      when "approved"
        "replacement_approved"
      when "in_transit"
        "replacement_shipped"
      when "received", "completed"
        "replacement_delivered"
      when "rejected", "cancelled"
        "delivered"
      else
        requestable.status
      end

    requestable.update!(status: order_status, status_note: @resolution_notes.presence || requestable.status_note)
  end

  def request_items(requestable)
    case requestable
    when Order
      requestable.order_items
    when B2bOrder
      requestable.b2b_order_items
    else
      raise StandardError, "Unsupported requestable type"
    end
  end

  def reserve_replacement_inventory!(request)
    request_items(request.requestable).find_each do |item|
      if item.dealer_product_id.present?
        dealer_product = DealerProduct.lock.find(item.dealer_product_id)
        if dealer_product.stock_quantity.to_i < item.quantity.to_i
          raise StandardError, "Insufficient stock for replacement"
        end
        dealer_product.update!(
          stock_quantity: dealer_product.stock_quantity.to_i - item.quantity.to_i
        )
      elsif item.wholesaler_post_id.present?
        post = WholesalerPost.lock.find(item.wholesaler_post_id)
        if post.stock_quantity.to_i < item.quantity.to_i
          raise StandardError, "Insufficient stock for replacement"
        end
        post.update!(
          stock_quantity: post.stock_quantity.to_i - item.quantity.to_i
        )
      else
        raise StandardError, "No inventory source found"
      end
    end
  end
end
