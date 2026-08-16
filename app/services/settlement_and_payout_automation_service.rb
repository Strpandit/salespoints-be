class SettlementAndPayoutAutomationService
  Result = Struct.new(:released_amount, :payout_created, :payout_id, :message, keyword_init: true)

  def initialize(order: nil, dealer: nil)
    @order = order
    @dealer = dealer
  end

  # Process all orders eligible for settlement release
  def self.process_pending_settlements!
    processed = 0
    failed = 0

    # Find all orders eligible for settlement
    Order
      .where(settlement_status: ["pending", "on_hold", "partially_refunded"])
      .where(payment_status: ["paid", "partially_refunded", "refunded"])
      .where("status" => ["processing", "shipped", "delivered"])
      .where("settlement_due_at IS NOT NULL AND settlement_due_at <= ?", Time.current)
      .find_each do |order|
        begin
          service = new(order: order)
          service.process_order_settlement!
          processed += 1
        rescue StandardError => e
          Rails.logger.error("Settlement processing error for order #{order.id}: #{e.message}")
          failed += 1
        end
      end

    {
      processed: processed,
      failed: failed,
      message: "Processed #{processed} orders, #{failed} failed"
    }
  end

  # Check and create automatic payouts for settled dealers
  def self.process_dealer_payouts!
    processed = 0
    failed = 0

    # Find dealers with sufficient settlement balance
    Dealer
      .where("settlement_balance > ?", MarketplaceOrderFinancials.minimum_payout_threshold)
      .find_each do |dealer|
        begin
          service = new(dealer: dealer)
          service.create_auto_payout_if_eligible!
          processed += 1
        rescue StandardError => e
          Rails.logger.error("Payout creation error for dealer #{dealer.id}: #{e.message}")
          failed += 1
        end
      end

    {
      processed: processed,
      failed: failed,
      message: "Created payouts for #{processed} dealers, #{failed} failed"
    }
  end

  # Process single order settlement
  def process_order_settlement!
    return unless @order.present?

    Order.transaction do
      order = Order.lock.includes(:seller_dealer, :return_requests).find(@order.id)
      
      # Re-validate eligibility after locking
      raise StandardError, "Order no longer eligible for settlement" unless settlement_eligible?(order)
      
      # Check for active return/exchange/refund requests
      if has_active_return_requests?(order)
        Rails.logger.info("Order #{order.id} has active return requests, holding settlement")
        return
      end

      # Release the hold
      released_amount = order.seller_settlement_amount.to_d
      
      OrderSettlementService.new(order: order).call
      order.reload

      Rails.logger.info("Released settlement of #{released_amount} for order #{order.id}")
    end
  end

  # Create automatic payout request if dealer meets criteria
  def create_auto_payout_if_eligible!
    return unless @dealer.present?

    Dealer.transaction do
      dealer = Dealer.lock.find(@dealer.id)
      balance = dealer.settlement_balance.to_d

      raise StandardError, "Insufficient balance for payout" unless balance > MarketplaceOrderFinancials.minimum_payout_threshold

      # Check if dealer has pending payouts
      if dealer.dealer_payouts.where(status: ["pending", "approved"]).exists?
        Rails.logger.info("Dealer #{dealer.id} has pending payouts, skipping auto-payout")
        return
      end

      # Create payout request
      payout = DealerPayoutService.new(dealer: dealer).request!(
        amount: balance,
        note: "Automatic payout for settled orders"
      )

      # Try to onboard to Cashfree if not already done
      onboard_to_cashfree!(dealer) if cashfree_payout_enabled?

      Result.new(
        released_amount: balance,
        payout_created: true,
        payout_id: payout.id,
        message: "Payout request created for dealer #{dealer.id}"
      )
    end
  rescue StandardError => e
    Rails.logger.error("Auto payout creation error: #{e.message}")
    Result.new(
      released_amount: 0,
      payout_created: false,
      payout_id: nil,
      message: e.message
    )
  end

  # Process payout through Cashfree
  def process_cashfree_payout!(payout:, admin:)
    Dealer.transaction do
      payout = DealerPayout.lock.includes(:dealer).find(payout.id)
      dealer = payout.dealer
      profile = dealer.dealer_profile
      
      raise StandardError, "Payout is not in approved status" unless payout.approved?
      raise StandardError, "Dealer bank account is not verified" unless profile&.bank_verified?

      DealerPayoutService.new(dealer: dealer).ensure_requestable_settlement_balance!(payout: payout, dealer: dealer)

      # Step 1: Ensure beneficiary is onboarded
      ensure_beneficiary_onboarded!(dealer)

      # Step 2: Request transfer
      transfer_id = "TRANSFER-#{payout.id}-#{SecureRandom.hex(4).upcase}"
      idempotency_key = "PAYOUT-#{payout.id}-#{Time.current.to_i}"

      transfer_response = CashfreeService.new.request_transfer(
        dealer: dealer,
        amount: payout.amount,
        transfer_id: transfer_id,
        idempotency_key: idempotency_key
      )

      payout.update!(
        status: "processing",
        processing_at: Time.current,
        payment_reference: transfer_id,
        payment_mode: "NEFT",
        processed_by_admin: admin,
        metadata: payout.metadata.merge({
          transfer_response: transfer_response,
          processing_started_at: Time.current.iso8601
        })
      )

      DealerPayoutNotificationService.status_updated!(payout.reload, actor: admin)

      # Step 3: Schedule status check
      CheckPayoutTransferStatusJob.set(wait: 2.minutes).perform_later(payout.id)

      payout.reload
    end
  rescue StandardError => e
    Rails.logger.error("Cashfree payout processing error: #{e.message}")
    raise
  end

  # Check transfer status and update payout
  def check_transfer_status!(payout:)
    payout = DealerPayout.lock.find(payout.id) if payout.is_a?(Integer)
    
    transfer_id = payout.payment_reference
    raise StandardError, "No transfer ID found for payout" unless transfer_id.present?

    status_response = CashfreeService.new.get_transfer_status(transfer_id: transfer_id)
    transfer_status = status_response["transfer_status"].to_s.upcase

    case transfer_status
    when "SUCCESS"
      mark_payout_as_paid!(payout, status_response)
    when "FAILED"
      mark_payout_as_failed!(payout, status_response)
    when "PENDING"
      # Schedule another check
      CheckPayoutTransferStatusJob.set(wait: 5.minutes).perform_later(payout.id) if payout.updated_at < 30.minutes.ago
    end

    payout.reload
  rescue StandardError => e
    Rails.logger.error("Transfer status check error: #{e.message}")
    raise
  end

  private

  def settlement_eligible?(order)
    return false unless order.payment_status.in?(%w[paid partially_refunded refunded])
    return false unless order.status.in?(%w[processing shipped delivered])
    return false unless order.settlement_status.in?(%w[pending on_hold partially_refunded])
    return false unless order.settlement_due_at.present? && order.settlement_due_at <= Time.current
    return false if order.seller_settlement_amount.to_d <= 0

    true
  end

  def has_active_return_requests?(order)
    order.return_requests.where(status: ["requested", "approved"]).exists?
  end

  def ensure_beneficiary_onboarded!(dealer)
    return unless cashfree_payout_enabled?

    # Check if beneficiary exists in Cashfree
    begin
      CashfreeService.new.get_beneficiary(dealer: dealer)
    rescue StandardError => e
      # Beneficiary doesn't exist, create one
      onboard_to_cashfree!(dealer)
    end
  end

  def onboard_to_cashfree!(dealer)
    return unless cashfree_payout_enabled?

    idempotency_key = "ONBOARD-#{dealer.id}-#{Time.current.to_i}"
    CashfreeService.new.add_beneficiary(
      dealer: dealer,
      idempotency_key: idempotency_key
    )

    dealer.update!(
      metadata: (dealer.metadata || {}).merge({
        cashfree_onboarded_at: Time.current.iso8601,
        cashfree_beneficiary_id: "DEAL-#{dealer.id}-#{dealer.dealer_code.presence || 'SELLER'}"
      })
    )
  end

  def mark_payout_as_paid!(payout, transfer_response)
    DealerPayoutService.new(dealer: payout.dealer).mark_paid!(
      payout: payout,
      admin: payout.processed_by_admin,
      payment_reference: payout.payment_reference,
      payment_mode: payout.payment_mode.presence || "NEFT",
      note: transfer_response["message"].presence
    )

    payout.update!(
      metadata: payout.metadata.merge({
        transfer_success_response: transfer_response,
        paid_at: Time.current.iso8601
      })
    )
  end

  def mark_payout_as_failed!(payout, transfer_response)
    payout.update!(
      status: "failed",
      processed_by_admin: payout.processed_by_admin,
      admin_note: [payout.admin_note, transfer_response["message"].presence || "Transfer failed"].compact.join("\n").presence,
      metadata: payout.metadata.merge({
        transfer_failure_response: transfer_response,
        failure_reason: transfer_response["message"].presence || "Transfer failed"
      })
    )

    DealerPayoutNotificationService.status_updated!(payout.reload, actor: payout.processed_by_admin)
  end

  def cashfree_payout_enabled?
    ENV["CASHFREE_PAYOUT_CLIENT_ID"].present? && ENV["CASHFREE_PAYOUT_CLIENT_SECRET"].present?
  end
end
