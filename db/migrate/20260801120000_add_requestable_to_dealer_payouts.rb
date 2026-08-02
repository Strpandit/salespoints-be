class AddRequestableToDealerPayouts < ActiveRecord::Migration[8.0]
  def change
    add_reference :dealer_payouts, :requestable, polymorphic: true, null: true
    add_column :dealer_payouts, :invoice_number, :string
  end
end
