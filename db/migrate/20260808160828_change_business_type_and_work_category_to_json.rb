class ChangeBusinessTypeAndWorkCategoryToJson < ActiveRecord::Migration[8.0]
  def up
    # First, handle empty strings and whitespace-only values
    execute <<-SQL
      UPDATE dealer_profiles 
      SET business_type = NULL 
      WHERE business_type IS NULL OR TRIM(business_type) = '';
    SQL

    execute <<-SQL
      UPDATE dealer_profiles 
      SET work_category = NULL 
      WHERE work_category IS NULL OR TRIM(work_category) = '';
    SQL

    # Convert remaining text data to proper JSON format
    execute <<-SQL
      UPDATE dealer_profiles 
      SET business_type = to_json(business_type::text)
      WHERE business_type IS NOT NULL;
    SQL

    execute <<-SQL
      UPDATE dealer_profiles 
      SET work_category = to_json(work_category::text)
      WHERE work_category IS NOT NULL;
    SQL

    # Change the column type
    change_column :dealer_profiles, :business_type, :json, using: 'business_type::json'
    change_column :dealer_profiles, :work_category, :json, using: 'work_category::json'
  end

  def down
    change_column :dealer_profiles, :business_type, :text
    change_column :dealer_profiles, :work_category, :text
  end
end