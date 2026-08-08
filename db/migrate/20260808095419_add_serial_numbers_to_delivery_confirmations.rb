class AddSerialNumbersToDeliveryConfirmations < ActiveRecord::Migration[8.0]
  def change
    add_column :delivery_confirmations, :serial_numbers, :string, array: true, default: []
  end
end
