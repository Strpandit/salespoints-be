class AccountIdnilToAddress < ActiveRecord::Migration[8.0]
  def change
    change_column_null :addresses, :account_id, true
  end
end
