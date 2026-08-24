class DealerPayoutSerializer < ApplicationSerializer
  attributes :request_number, :amount, :status, :bank_name, :bank_account_number, :ifsc_code,
             :account_holder_name, :payment_reference, :payment_mode, :admin_note,
             :approved_at, :processing_at, :paid_at, :rejected_at, :cancelled_at,
             :created_at, :updated_at, :dealer_id, :dealer_name, :dealer_code, :order_reference,
             :request_flow, :invoice_number, :gst_invoice, :requestable_type, :requestable_id,
             :bank_verification_status, :bank_verified, :settlement_ready_for_processing,
             :selected_orders, :total_gross, :total_commission, :penalty, :net_payout,
             :payout_mode, :is_cod, :adjusted_cod_details

  def amount
    object.amount.to_f
  end

  def dealer_id
    object.dealer_id
  end

  def dealer_name
    object.dealer&.full_name
  end

  def dealer_code
    object.dealer&.dealer_code
  end

  def order_reference
    object.order_reference
  end

  def request_flow
    object.request_flow
  end

  def selected_orders
    raw_orders = (object.metadata || {})["selected_orders"] || []
    if raw_orders.empty? && object.requestable.present?
      breakdown = DealerPayoutService.new(dealer: object.dealer).calculate_order_financials(object.requestable)
      raw_orders = [{
        "order_id" => object.requestable_id,
        "order_type" => object.requestable_type == "Order" ? "b2c" : "b2b",
        "reference_number" => object.order_reference || "##{object.requestable_id}",
        "flow_type" => object.request_flow || "b2c",
        "buyer_name" => object.requestable.try(:buyer)&.try(:full_name) || "Buyer",
        "payment_method" => object.requestable.try(:payment_method).presence || "online",
        "payment_status" => object.requestable.try(:payment_status) || "paid",
        "gross_amount" => breakdown[:gross_amount].to_f,
        "commission_rate" => (breakdown[:commission_rate] * 100).to_f,
        "commission_fee" => breakdown[:commission_fee].to_f,
        "net_payout_amount" => breakdown[:net_payout_amount].to_f,
        "created_at" => object.requestable.created_at&.iso8601,
        "delivered_at" => object.requestable.try(:delivered_at)&.iso8601
      }]
    end

    raw_orders.map do |ord|
      item = ord.is_a?(Hash) ? ord.dup : {}
      item.delete("commission_gst")
      unless item.key?("payment_method") && item.key?("created_at")
        actual_order =
          if item["order_type"].to_s.downcase.in?(%w[b2c order retail])
            Order.find_by(id: item["order_id"])
          else
            B2bOrder.find_by(id: item["order_id"])
          end

        if actual_order
          item["payment_method"] ||= actual_order.try(:payment_method).presence || "online"
          item["payment_status"] ||= actual_order.try(:payment_status) || "paid"
          item["created_at"] ||= actual_order.created_at&.iso8601
          item["delivered_at"] ||= actual_order.try(:delivered_at)&.iso8601
          item["order_status"] ||= actual_order.status
        else
          item["payment_method"] ||= "online"
          item["payment_status"] ||= "paid"
        end
      end
      item
    end
  end

  def total_gross
    ((object.metadata || {})["total_gross"] || object.amount).to_f
  end

  def total_commission
    ((object.metadata || {})["total_commission"] || 0.0).to_f
  end

  def penalty
    ((object.metadata || {})["penalty"] || 0.0).to_f
  end

  def net_payout
    ((object.metadata || {})["net_payout"] || object.amount).to_f
  end

  def gst_invoice
    return nil unless object.gst_invoice.attached?

    host = options[:base_url] || Rails.application.config.active_storage.default_url_options&.dig(:host)
    {
      id: object.gst_invoice.id,
      url: Rails.application.routes.url_helpers.rails_blob_url(object.gst_invoice, host: host),
      filename: object.gst_invoice.filename.to_s,
      content_type: object.gst_invoice.content_type.to_s
    }
  end

  def bank_verification_status
    object.dealer&.dealer_profile&.bank_verification_status
  end

  def bank_verified
    object.dealer&.dealer_profile&.bank_verified? || false
  end

  def settlement_ready_for_processing
    profile = object.dealer&.dealer_profile
    bank_ready = profile&.bank_verified?
    status_ready = object.status.to_s == "approved"

    bank_ready && status_ready
  end

  def payout_mode
    if (object.metadata || {})["payout_mode"].present?
      return object.metadata["payout_mode"]
    end
    DealerPayoutService.new(dealer: object.dealer).payout_is_cod?(object) ? "postpaid" : "prepaid"
  end

  def is_cod
    payout_mode == "postpaid"
  end

  def adjusted_cod_details
    cod_ids = (object.metadata || {})["adjusted_cod_payout_ids"] || []
    return [] if cod_ids.blank?
    DealerPayout.where(id: cod_ids).map do |cp|
      {
        id: cp.id,
        request_number: cp.request_number,
        amount: cp.amount.to_f,
        order_reference: cp.order_reference,
        created_at: cp.created_at&.iso8601,
        paid_at: cp.paid_at&.iso8601
      }
    end
  rescue StandardError
    []
  end
end
