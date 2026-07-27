module Api
  class PaymentsController < ApplicationController
    skip_before_action :authenticate_request!, only: [:cashfree_webhook, :payment_details, :verify_cashfree]

    def verify_cashfree
      if params[:payment_attempt_id].present?
        return verify_payment_attempt!
      end

      order = scoped_orders.find_by(id: params[:order_id])
      return render json: { error: "Order not found" }, status: :not_found unless order
      return render json: { error: "Cashfree reference missing" }, status: :unprocessable_entity if order.gateway_order_reference.blank?

      payload = CashfreeService.new.fetch_order(order.gateway_order_reference)
      status = payload["order_status"].to_s.upcase

      case status
      when "PAID"
        order.mark_payment_paid!(reference: payload["cf_payment_id"] || payload["payment_id"], gateway_payload: payload)
        if order.status == "pending"
          OrderLifecycleService.new(
            order: order,
            actor: current_user,
            status_note: "Online payment confirmed successfully."
          ).transition!(next_status: "processing")
          OrderMailer.customer_order_confirmation(order.id).deliver_later if order.buyer&.email.present?
          OrderMailer.dealer_new_order(order.id).deliver_later if order.seller_dealer&.email.present?
          OrderMailer.admin_order_alert(order.id).deliver_later
        end
      when "ACTIVE"
        order.update!(payment_gateway_payload: order.payment_gateway_payload.merge(payload))
      else
        order.mark_payment_failed!(gateway_payload: payload)
      end

      render json: {
        data: serialize_data(order.reload, OrderSerializer),
        payment_gateway_status: status
      }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def cancel_cashfree
      attempt = scoped_payment_attempts.find_by(id: params[:payment_attempt_id])
      return render json: { error: "Payment attempt not found" }, status: :not_found unless attempt

      attempt.update!(
        status: "cancelled",
        cancelled_at: Time.current,
        failure_reason: params[:reason].presence || "Payment cancelled by user"
      ) unless attempt.terminal?

      render json: {
        data: serialize_payment_attempt(attempt),
        message: "Payment cancelled"
      }, status: :ok
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def cashfree_webhook
      begin
        service = CashfreeWebhookProcessingService.new(
          headers: request.headers, 
          raw_body: request.raw_post
        )
        service.call
      rescue StandardError => e
        Rails.logger.error e.backtrace.join("\n")
      end
      head :ok
    end

    def payment_details
      order = B2bOrder.find_by(payment_token: params[:payment_token])

      return render json: { error: "Invalid payment link" }, status: :not_found unless order
      return render json: { error: "Order cancelled" }, status: :unprocessable_entity if order.status == "cancelled"
      return render json: { error: "Order rejected" }, status: :unprocessable_entity if order.request_status == "rejected_request"
      return render json: { error: "Payment already completed" }, status: :unprocessable_entity if order.payment_status == "paid"
      return render json: { error: "Payment link expired" }, status: :unprocessable_entity if order.expires_at.present? && order.expires_at < Time.current

      if order.total_amount > 50000 && order.payment_method == "cod"
        cod_allowed = false
      else
        cod_allowed = true
      end

      items = order.b2b_order_items

      render json: {
        order_id: order.id,
        payment_token: order.payment_token,
        amount: order.total_amount,
        payment_status: order.payment_status,
        payment_method: order.payment_method,
        request_status: order.request_status,
        expires_at: order.expires_at,
        cod_allowed: cod_allowed,
        items: B2bOrderItemSerializer.render(items)
      }
    end

    private

    def verify_payment_attempt!
      attempt =
        if current_admin || current_dealer || current_account
          scoped_payment_attempts.find_by(id: params[:payment_attempt_id])
        else
          order = B2bOrder.find_by(payment_token: params[:payment_token])

          return render json: { error: "Invalid payment link" }, status: :not_found unless order
          return render json: { error: "Payment already completed" }, status: :unprocessable_entity if order.payment_status == "paid"
          return render json: { error: "Payment link expired" }, status: :unprocessable_entity if order.expires_at.present? && order.expires_at <= Time.current

          PaymentAttempt.find_by(
            id: params[:payment_attempt_id],
            buyer: order.buyer_dealer,
            b2b_order_id: order.id
          )
        end

      return render json: { error: "Payment attempt not found" }, status: :not_found unless attempt
      return render json: { error: "Cashfree reference missing" }, status: :unprocessable_entity if attempt.gateway_order_reference.blank?

      payload = CashfreeService.new.fetch_order(attempt.gateway_order_reference)
      status = payload["order_status"].to_s.upcase

      case status
      when "PAID"
        mark_attempt_paid!(attempt, payload)
        finalization = PaymentAttemptFinalizationService.new(payment_attempt: attempt).call
        if finalization.b2b_order.present?
          finalization.b2b_order.update!(
            payment_reference: payload.dig("payment", "cf_payment_id") || payload["cf_payment_id"] || payload["payment_id"],
            payment_gateway_payload: payload,
            payment_token: SecureRandom.hex(32),
            expires_at: Time.current
          )

          EmailDispatcherService.b2b_payment_done(finalization.b2b_order)

          return render json: {
            data: B2bOrderSerializer.render(finalization.b2b_order),
            b2b_order: B2bOrderSerializer.render(finalization.b2b_order),
            payment_attempt: serialize_payment_attempt(attempt.reload),
            payment_gateway_status: status,
            message: "B2B request broadcasted after successful payment"
          }, status: :ok
        end
        finalization.orders.each do |order|
          EmailDispatcherService.retail_order_placed(order)
        end

        render json: {
          data: OrderSerializer.render(finalization.orders),
          orders: OrderSerializer.render(finalization.orders),
          payment_attempt: serialize_payment_attempt(attempt.reload),
          payment_gateway_status: status,
          message: "#{finalization.orders.size} order(s) created after successful payment"
        }, status: :ok

      when "ACTIVE"
        attempt.update!(payment_gateway_payload: attempt.payment_gateway_payload.merge(payload))
        render json: {
          data: serialize_payment_attempt(attempt.reload),
          payment_attempt: serialize_payment_attempt(attempt.reload),
          payment_gateway_status: status,
          message: "Payment is still pending"
        }, status: :ok
      else
        mark_attempt_failed!(attempt, payload, status)
        render json: {
          data: serialize_payment_attempt(attempt.reload),
          payment_attempt: serialize_payment_attempt(attempt.reload),
          payment_gateway_status: status,
          message: "Payment failed."
        }, status: :ok
      end
    end

    def mark_attempt_paid!(attempt, payload)
      return if attempt.processed?

      attempt.update!(
        status: "paid",
        paid_at: attempt.paid_at || Time.current,
        payment_reference: payload.dig("payment", "cf_payment_id") || payload["cf_payment_id"] || payload["payment_id"] || attempt.payment_reference,
        payment_gateway_payload: attempt.payment_gateway_payload.merge(payload || {})
      )
    end

    def mark_attempt_failed!(attempt, payload, status)
      terminal_state = status.in?(%w[CANCELLED USER_DROPPED]) ? "cancelled" : "failed"
      attrs = {
        status: terminal_state,
        payment_gateway_payload: attempt.payment_gateway_payload.merge(payload || {}),
        failure_reason: status.presence || "Payment failed"
      }
      attrs[:cancelled_at] = Time.current if terminal_state == "cancelled"
      attrs[:failed_at] = Time.current if terminal_state == "failed"
      attempt.update!(attrs) unless attempt.terminal?
    end

    def serialize_payment_attempt(attempt)
      {
        id: attempt.id,
        attempt_number: attempt.attempt_number,
        status: attempt.status,
        amount: attempt.amount.to_f,
        payment_reference: attempt.payment_reference,
        failure_reason: attempt.failure_reason,
        processed_at: attempt.processed_at,
        paid_at: attempt.paid_at
      }
    end

    def scoped_orders
      if current_admin
        Order.all
      elsif current_dealer
        Order.where(buyer: current_dealer).or(Order.where(seller_dealer_id: current_dealer.id))
      elsif current_account
        current_account.orders
      else
        Order.none
      end
    end

    def scoped_payment_attempts
      if current_admin
        PaymentAttempt.all
      elsif current_dealer
        current_dealer.payment_attempts
      elsif current_account
        current_account.payment_attempts
      else
        PaymentAttempt.none
      end
    end

    def unauthorized_webhook_error?(error)
      error.message.match?(/signature|timestamp/i)
    end
  end
end
