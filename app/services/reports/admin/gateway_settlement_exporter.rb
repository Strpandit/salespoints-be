module Reports
  module Admin
    class GatewaySettlementExporter < Reports::BaseExporter
      def generate
        range = date_range

        headers = ["Provider", "Event Type", "Event ID", "Status", "Received At", "Processed At"]
        rows = PaymentGatewayWebhookEvent.where(created_at: range).order(created_at: :desc).map do |e|
          [
            e.provider.to_s.titleize,
            e.event_type.to_s,
            e.event_id,
            e.status.capitalize,
            e.received_at&.strftime("%d %b %Y %H:%M") || e.created_at.strftime("%d %b %Y"),
            e.processed_at&.strftime("%d %b %Y %H:%M") || "—"
          ]
        end

        { title: "Admin Payment Gateway Settlements Log", headers: headers, rows: rows }
      end
    end
  end
end
