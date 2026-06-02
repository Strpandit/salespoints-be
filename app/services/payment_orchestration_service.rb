class PaymentOrchestrationService
  Result = Struct.new(:success?, :payment_attempt, :orders, :error_message, keyword_init: true)

  def initialize(buyer:, items_data:, payment_method:, use_wallet: false)
    @buyer = buyer
    @items_data = items_data
    @payment_method = payment_method
    @use_wallet = use_wallet
    @transaction_id = SecureRandom.uuid
  end

  # Main orchestration method
  def execute!
    Order.transaction do
      raise StandardError, "Invalid buyer" unless @buyer.present?
      raise StandardError, "Invalid payment method" unless valid_payment_method?
      
      # Step 1: Create orders
      orders = create_orders!
      raise StandardError, "No orders created" if orders.blank?

      # Step 2: Create payment attempt
      payment_attempt = create_payment_attempt!(orders)
      raise StandardError, "Failed to create payment attempt" unless payment_attempt.present?

      # Step 3: Initiate payment gateway session
      payment_session = initiate_payment_session!(payment_attempt)
      raise StandardError, "Failed to create payment session" unless payment_session.present?

      payment_attempt.update!(
        gateway_order_reference: payment_session["order_id"],
        payment_gateway_payload: payment_session
      )

      Result.new(
        success?: true,
        payment_attempt: payment_attempt,
        orders: orders,
        error_message: nil
      )
    end
  rescue StandardError => e
    Rails.logger.error("Payment Orchestration Error: #{e.message}\n#{e.backtrace.join("\n")}")
    Result.new(
      success?: false,
      payment_attempt: nil,
      orders: [],
      error_message: e.message
    )
  end

  # Verify payment and finalize orders
  def verify_and_finalize!(payment_attempt:)
    Order.transaction do
      raise StandardError, "Payment attempt not found" unless payment_attempt.present?

      # Verify with payment gateway
      gateway_payload = verify_with_gateway!(payment_attempt)
      payment_status = extract_payment_status(gateway_payload)

      case payment_status
      when "SUCCESS"
        finalize_successful_payment!(payment_attempt, gateway_payload)
      when "FAILED"
        finalize_failed_payment!(payment_attempt, gateway_payload)
      when "PENDING"
        payment_attempt.update!(payment_gateway_payload: gateway_payload)
      end

      payment_attempt.reload
    end
  rescue StandardError => e
    Rails.logger.error("Payment Verification Error: #{e.message}")
    raise
  end

  private

  def valid_payment_method?
    @payment_method.in?(%w[cod online wallet])
  end

  def create_orders!
    orders = []
    total_amount = 0

    @items_data.group_by { |item| item[:dealer_id] }.each do |dealer_id, dealer_items|
      dealer = Dealer.find_by(id: dealer_id)
      raise StandardError, "Dealer #{dealer_id} not found" unless dealer.present?

      order_data = {
        buyer: @buyer,
        seller_dealer: dealer,
        payment_method: @payment_method,
        payment_status: "pending",
        status: "pending"
      }

      # Calculate amounts
      order_items_data = dealer_items.map do |item|
        {
          dealer_product_id: item[:product_id],
          quantity: item[:quantity],
          price: item[:price]
        }
      end

      order = Order.new(order_data)
      order.order_items.build(order_items_data)
      
      # Calculate totals
      subtotal = order.order_items.sum { |oi| oi.quantity * oi.price }
      commission_rate = determine_commission_rate(dealer)
      commission = (subtotal * commission_rate / 100).round(2)
      marketplace_fee = (subtotal * MarketplaceOrderFinancials.marketplace_fee_rate / 100).round(2)
      seller_settlement = (subtotal - commission - marketplace_fee).round(2)

      order.update!(
        total_amount: subtotal,
        commission_rate: commission_rate,
        commission_amount: commission,
        marketplace_fee_amount: marketplace_fee,
        seller_settlement_amount: seller_settlement,
        settlement_status: "on_hold",
        return_window_closes_at: nil  # Will be set after delivery
      )

      order.save!
      orders << order
      total_amount += subtotal
    end

    orders
  end

  def create_payment_attempt!(orders)
    total_amount = orders.sum(&:total_amount)

    PaymentAttempt.create!(
      buyer: @buyer,
      amount: total_amount,
      payment_gateway: @payment_method == "online" ? "cashfree" : "manual",
      status: "pending",
      payment_method: @payment_method,
      transaction_id: @transaction_id,
      metadata: {
        order_ids: orders.map(&:id),
        buyer_type: @buyer.class.name,
        buyer_id: @buyer.id
      }
    )
  end

  def initiate_payment_session!(payment_attempt)
    case @payment_method
    when "online"
      CashfreeService.new.create_payment_attempt(
        attempt: payment_attempt,
        customer: @buyer
      )
    when "cod"
      # For COD, no session needed
      {
        "order_id" => payment_attempt.attempt_number,
        "payment_session_id" => "COD-#{payment_attempt.id}",
        "payment_method" => "cod"
      }
    when "wallet"
      # Validate wallet balance
      raise StandardError, "Insufficient wallet balance" unless has_sufficient_wallet_balance?(payment_attempt.amount)
      {
        "order_id" => payment_attempt.attempt_number,
        "payment_session_id" => "WALLET-#{payment_attempt.id}",
        "payment_method" => "wallet"
      }
    end
  end

  def verify_with_gateway!(payment_attempt)
    case payment_attempt.payment_method
    when "online"
      CashfreeService.new.fetch_order(payment_attempt.gateway_order_reference)
    when "cod"
      { "order_status" => "ACTIVE", "order_id" => payment_attempt.attempt_number }
    when "wallet"
      # Process wallet payment immediately
      deduct_wallet_balance!(payment_attempt.amount)
      { "order_status" => "PAID", "payment_method" => "wallet" }
    end
  end

  def finalize_successful_payment!(payment_attempt, gateway_payload)
    payment_attempt.update!(
      status: "paid",
      paid_at: payment_attempt.paid_at || Time.current,
      payment_reference: extract_payment_reference(gateway_payload),
      payment_gateway_payload: gateway_payload
    )

    # Mark all orders as paid
    Order.where(id: payment_attempt.metadata["order_ids"]).each do |order|
      order.update!(
        payment_status: "paid",
        status: "processing"
      )

      # Trigger processing notifications
      OrderNotificationJob.perform_later(order.id, "placed", order.buyer_type, order.buyer_id)
      OrderNotificationJob.perform_later(order.id, "payment_paid", order.buyer_type, order.buyer_id)
    end
  end

  def finalize_failed_payment!(payment_attempt, gateway_payload)
    payment_attempt.update!(
      status: "failed",
      failure_reason: extract_failure_reason(gateway_payload),
      payment_gateway_payload: gateway_payload
    )

    # Cancel all orders
    Order.where(id: payment_attempt.metadata["order_ids"]).each do |order|
      order.update!(
        payment_status: "failed",
        status: "cancelled"
      )
    end
  end

  def extract_payment_status(payload)
    (payload["order_status"] || payload["payment_status"])&.to_s&.upcase
  end

  def extract_payment_reference(payload)
    payload["cf_payment_id"] || payload["payment_id"] || payload["order_id"]
  end

  def extract_failure_reason(payload)
    payload["error_message"] || payload["error"] || "Payment processing failed"
  end

  def determine_commission_rate(dealer)
    dealer.commission_rate || MarketplaceOrderFinancials.default_commission_rate
  end

  def has_sufficient_wallet_balance?(amount)
    # Implement wallet balance check
    true
  end

  def deduct_wallet_balance!(amount)
    # Implement wallet deduction
  end
end
