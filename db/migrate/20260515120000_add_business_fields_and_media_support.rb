class AddBusinessFieldsAndMediaSupport < ActiveRecord::Migration[8.0]
  def up
    add_column :dealer_profiles, :work_category, :string
    add_column :dealer_profiles, :associated_brands, :string
    add_reference :ticket_messages, :dealer, foreign_key: true

    say_with_time "Backfilling dealer codes to SPIN format" do
      dealer_class = Class.new(ActiveRecord::Base) do
        self.table_name = "dealers"
      end

      dealer_class.reset_column_information
      dealer_class.order(:created_at, :id).find_each.with_index(1) do |dealer, index|
        dealer.update_columns(dealer_code: format("SPIN%04d", index))
      end
    end
  end

  def down
    remove_reference :ticket_messages, :dealer, foreign_key: true
    remove_column :dealer_profiles, :associated_brands
    remove_column :dealer_profiles, :work_category
  end
end
