class FixDeliveryConfirmationsUniqueIndex < ActiveRecord::Migration[7.0]
  def change
    remove_index :delivery_confirmations, name: "idx_delivery_confirmations_on_deliverable", if_exists: true
    add_index :delivery_confirmations, [:deliverable_type, :deliverable_id, :context], unique: true, name: "idx_delivery_confirmations_on_deliverable_context", if_not_exists: true
  end
end
