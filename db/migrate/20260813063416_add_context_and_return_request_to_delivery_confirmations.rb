class AddContextAndReturnRequestToDeliveryConfirmations < ActiveRecord::Migration[8.0]
  def change
    add_column :delivery_confirmations, :context, :string, default: "original", null: false
    add_column :delivery_confirmations, :return_request_id, :bigint, null: true

    add_index :delivery_confirmations, :context
    add_index :delivery_confirmations, :return_request_id, where: "return_request_id IS NOT NULL"

    reversible do |dir|
      dir.up { execute "UPDATE delivery_confirmations SET context = 'original' WHERE context IS NULL OR context = ''" }
    end
  end
end
