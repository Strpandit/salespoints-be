class AddDealerCodeToDealers < ActiveRecord::Migration[8.0]
  def up
    add_column :dealers, :dealer_code, :string
    add_index :dealers, :dealer_code, unique: true

    say_with_time "Backfilling dealer_code for existing dealers" do
      dealer_model = Class.new(ActiveRecord::Base) { self.table_name = "dealers" }
      dealer_model.reset_column_information
      dealer_model.find_each do |dealer|
        next if dealer.dealer_code.present?

        loop do
          candidate = format("%06d", rand(0..999_999))
          next if dealer_model.exists?(dealer_code: candidate)

          dealer.update_columns(dealer_code: candidate)
          break
        end
      end
    end

    change_column_null :dealers, :dealer_code, false
  end

  def down
    remove_index :dealers, :dealer_code
    remove_column :dealers, :dealer_code
  end
end
