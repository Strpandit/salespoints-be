namespace :data_migration do
  desc "Migrate colors for existing stock"
  task migrate_inventory: :environment do
    puts "Starting data migration..."

    puts "Migrating product variant colors..."
    ProductVariant.find_each do |variant|
      colors = variant.colors.presence || ['Standard']
      colors.each do |color_name|
        # Create a default product variant color if it doesn't exist
        variant.product_variant_colors.find_or_create_by!(color_name: color_name) do |pvc|
          pvc.sku_code = "#{variant.variant_sku}-#{color_name.parameterize.upcase}"
        end
      end
    end
    puts "Colors migration complete."
    
    puts "Data migration finished successfully!"
  end
end
