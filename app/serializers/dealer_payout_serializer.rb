class DealerPayoutSerializer < ApplicationSerializer
  attributes :request_number, :amount, :status, :bank_name, :bank_account_number, :ifsc_code,
             :account_holder_name, :payment_reference, :payment_mode, :admin_note,
             :approved_at, :processing_at, :paid_at, :rejected_at, :cancelled_at,
             :created_at, :updated_at, :dealer_name, :dealer_code, :order_reference,
             :request_flow, :invoice_number, :gst_invoice, :requestable_type, :requestable_id

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
end
