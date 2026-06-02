class AddAttemptsToPaymentGatewayWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :payment_gateway_webhook_events, :attempts, :integer, default: 0, null: false
  end
end
