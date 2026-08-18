class AddReplacementFieldsToReturnRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :return_requests, :replacement_mode, :string, default: "full", null: false
    add_column :return_requests, :defective_quantity, :integer, default: 1, null: false
    add_column :return_requests, :defective_serial_numbers, :json, default: []
    add_column :return_requests, :replacement_serial_numbers, :json, default: []

    add_index :return_requests, :replacement_mode
  end
end
