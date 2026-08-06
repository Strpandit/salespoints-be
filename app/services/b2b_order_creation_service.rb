class B2bOrderCreationService
  def initialize(request_order:, payment_method:, payment_status:, buyer_payment_attempt: nil)
    @request_order = request_order
    @payment_method = payment_method.to_s
    @payment_status = payment_status.to_s
    @buyer_payment_attempt = buyer_payment_attempt
  end

  def call
    Rails.logger.info "🚀 B2bOrderCreationService.call STARTED"
    Rails.logger.info "📦 Order ID: #{@request_order&.id}"
    Rails.logger.info "💳 Payment Method: #{@payment_method}"
    Rails.logger.info "💵 Payment Status: #{@payment_status}"
    
    raise StandardError, "Request order not found" unless @request_order

    final_order = nil

    ActiveRecord::Base.transaction do
      Rails.logger.info "🔄 Transaction STARTED"
      
      request_order = B2bOrder.lock.find(@request_order.id)
      Rails.logger.info "✅ Order locked: ID #{request_order.id}, Status: #{request_order.status}"

      ensure_request_ready!(request_order)
      Rails.logger.info "✅ ensure_request_ready! PASSED"

      final_order = request_order

      request_order.b2b_order_items.accepted_items.order(:id).each do |request_item|
        Rails.logger.info "📝 Processing item ID: #{request_item.id}"
        Rails.logger.info "   dealer_product_id: #{request_item.dealer_product_id.inspect}"
        Rails.logger.info "   product_variant_id: #{request_item.product_variant_id}"
        Rails.logger.info "   status: #{request_item.status}"
        
        begin
          source, dealer_product_id = resolve_source!(request_item)
          Rails.logger.info "✅ resolve_source! SUCCESS: dealer_product_id = #{dealer_product_id.inspect}"
          
          request_item.update!(
            dealer_product_id: dealer_product_id,
            status: "accepted",
            responded_at: request_item.responded_at || Time.current
          )
          Rails.logger.info "✅ request_item.update! SUCCESS"
          
          unless request_order.is_direct_buy?
            Rails.logger.info "📊 Deducting stock for item #{request_item.id}"
            deduct_stock!(request_item)
            Rails.logger.info "✅ deduct_stock! SUCCESS"
          end
        rescue StandardError => e
          Rails.logger.error "❌ Error processing item #{request_item.id}: #{e.message}"
          Rails.logger.error "   Backtrace: #{e.backtrace.first(5).join("\n   ")}"
          raise e
        end
      end

      Rails.logger.info "📊 Recalculating totals..."
      final_order.recalculate_totals!
      Rails.logger.info "✅ recalculate_totals! SUCCESS"

      Rails.logger.info "📝 Updating order payment details..."
      request_order.update!(
        payment_method: @payment_method,
        buyer_payment_attempt: @buyer_payment_attempt
      )
      Rails.logger.info "✅ order.update! SUCCESS"

      if @payment_status == "paid"
        Rails.logger.info "💰 Marking payment as paid..."
        request_order.mark_payment_paid!
        Rails.logger.info "✅ mark_payment_paid! SUCCESS"
      end

      unless request_order.is_direct_buy?
        Rails.logger.info "✅ Marking order as confirmed..."
        request_order.mark_order_confirmed!
        Rails.logger.info "✅ mark_order_confirmed! SUCCESS"
      end

      Rails.logger.info "🔄 Transaction COMMITTED successfully!"
      final_order
    end
    
    Rails.logger.info "🎉 B2bOrderCreationService.call COMPLETED successfully!"
    final_order
    
  rescue StandardError => e
    Rails.logger.error "❌ B2bOrderCreationService.call FAILED: #{e.message}"
    Rails.logger.error "   Backtrace: #{e.backtrace.join("\n   ")}"
    raise e
  end
  
  private

  def resolve_source!(request_item)
    Rails.logger.info "🔍 resolve_source! called for item #{request_item.id}"
    Rails.logger.info "   wholesaler_post_id: #{request_item.wholesaler_post_id.inspect}"
    Rails.logger.info "   dealer_product_id: #{request_item.dealer_product_id.inspect}"
    
    if request_item.wholesaler_post_id.present?
      Rails.logger.info "📦 Resolving via wholesaler_post_id: #{request_item.wholesaler_post_id}"
      wholesaler_post = WholesalerPost.lock.find_by(id: request_item.wholesaler_post_id)
      raise StandardError, "Wholesaler post not found" unless wholesaler_post
      Rails.logger.info "✅ WholesalerPost found: #{wholesaler_post.id}"
      
      raise StandardError, "Dealer product missing for wholesaler post #{wholesaler_post.id}" if wholesaler_post.dealer_product_id.blank?
      Rails.logger.info "✅ Resolved to dealer_product_id: #{wholesaler_post.dealer_product_id}"
      [wholesaler_post, wholesaler_post.dealer_product_id]
      
    elsif request_item.dealer_product_id.present?
      Rails.logger.info "🏷️ Resolving via dealer_product_id: #{request_item.dealer_product_id}"
      
      # 🔥 TRY 1: Without lock
      dealer_product = DealerProduct.find_by(id: request_item.dealer_product_id)
      Rails.logger.info "   Try 1 (without lock): #{dealer_product&.id.inspect}"
      
      # 🔥 TRY 2: With lock
      if dealer_product.blank?
        Rails.logger.info "   Try 2 (with lock)..."
        dealer_product = DealerProduct.lock.find_by(id: request_item.dealer_product_id)
        Rails.logger.info "   Try 2 result: #{dealer_product&.id.inspect}"
      end
      
      # 🔥 TRY 3: Fallback
      if dealer_product.blank?
        Rails.logger.info "   Try 3 (fallback)..."
        dealer_product = DealerProduct.active
          .where(product_variant_id: request_item.product_variant_id)
          .first
        Rails.logger.info "   Try 3 result: #{dealer_product&.id.inspect}"
        
        if dealer_product.present?
          Rails.logger.info "   ✅ Updating item with fallback dealer_product_id: #{dealer_product.id}"
          request_item.update!(dealer_product_id: dealer_product.id)
        end
      end
      
      raise StandardError, "Dealer product not found for ID #{request_item.dealer_product_id}" unless dealer_product
      Rails.logger.info "✅ Resolved to dealer_product_id: #{dealer_product.id}"
      [dealer_product, dealer_product.id]
      
    else
      Rails.logger.info "❌ No source found for item #{request_item.id}"
      raise StandardError, "Cannot resolve source for request item #{request_item.id}"
    end
  end

  def deduct_stock!(request_item)
    Rails.logger.info "📊 deduct_stock! called for item #{request_item.id}"
    
    if request_item.wholesaler_post_id.present?
      Rails.logger.info "   Deducting from wholesaler_post_id: #{request_item.wholesaler_post_id}"
      wholesaler_post = WholesalerPost.lock.find_by(id: request_item.wholesaler_post_id)
      raise StandardError, "Wholesaler post not found" unless wholesaler_post
      
      current_stock = wholesaler_post.stock_quantity.to_i
      requested_qty = request_item.quantity.to_i
      Rails.logger.info "   Current stock: #{current_stock}, Requested: #{requested_qty}"
      
      if current_stock < requested_qty
        raise StandardError, "Insufficient stock for wholesaler buy #{wholesaler_post.id}"
      end
      
      new_stock = current_stock - requested_qty
      wholesaler_post.update!(stock_quantity: new_stock)
      Rails.logger.info "✅ Stock updated: #{current_stock} → #{new_stock}"
      
    elsif request_item.dealer_product_id.present?
      Rails.logger.info "   Deducting from dealer_product_id: #{request_item.dealer_product_id}"
      dealer_product = DealerProduct.lock.find_by(id: request_item.dealer_product_id)
      raise StandardError, "Dealer product not found" unless dealer_product
      
      current_stock = dealer_product.stock_quantity.to_i
      requested_qty = request_item.quantity.to_i
      Rails.logger.info "   Current stock: #{current_stock}, Requested: #{requested_qty}"
      
      if current_stock < requested_qty
        raise StandardError, "Insufficient stock for dealer product #{dealer_product.id}"
      end
      
      new_stock = current_stock - requested_qty
      dealer_product.update!(stock_quantity: new_stock)
      Rails.logger.info "✅ Stock updated: #{current_stock} → #{new_stock}"
      
    else
      Rails.logger.error "❌ Cannot deduct stock: no source found"
      raise StandardError, "Cannot deduct stock: no source found for request item #{request_item.id}"
    end
  end
end