class ChangeBusinessTypeAndWorkCategoryToJson < ActiveRecord::Migration[8.0]
  def up
    # First, convert existing text data to proper JSON format
    execute <<-SQL
      UPDATE dealer_profiles 
      SET business_type = to_json(business_type::text)
      WHERE business_type IS NOT NULL AND business_type != '';
    SQL

    execute <<-SQL
      UPDATE dealer_profiles 
      SET work_category = to_json(work_category::text)
      WHERE work_category IS NOT NULL AND work_category != '';
    SQL

    # Now change the column type
    change_column :dealer_profiles, :business_type, :json, using: 'business_type::json'
    change_column :dealer_profiles, :work_category, :json, using: 'work_category::json'
  end

  def down
    change_column :dealer_profiles, :business_type, :text
    change_column :dealer_profiles, :work_category, :text
  end
end