class DealerPayoutSerializer < ApplicationSerializer
  attributes :request_number, :amount, :status, :bank_name, :bank_account_number, :ifsc_code,
             :account_holder_name, :payment_reference, :payment_mode, :admin_note,
             :approved_at, :processing_at, :paid_at, :rejected_at, :cancelled_at,
             :created_at, :updated_at, :dealer_name, :dealer_code, :order_reference,
             :request_flow, :invoice_number, :gst_invoice, :requestable_type, :requestable_id,
             :bank_verification_status, :bank_verified, :settlement_ready_for_processing,
             :selected_orders, :total_gross, :total_commission, :total_commission_gst, :penalty, :net_payout

  def amount
    object.amount.to_f
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
    (object.metadata || {})["selected_orders"] || []
  end

  def total_gross
    ((object.metadata || {})["total_gross"] || object.amount).to_f
  end

  def total_commission
    ((object.metadata || {})["total_commission"] || 0.0).to_f
  end

  def total_commission_gst
    ((object.metadata || {})["total_commission_gst"] || 0.0).to_f
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
end
