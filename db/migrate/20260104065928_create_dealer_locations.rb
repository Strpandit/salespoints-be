class CreateDealerLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :dealer_locations do |t|
      t.references :dealer, foreign_key: true
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.integer :service_radius_km, default: 5
      t.boolean :is_active, default: true

      t.timestamps
    end
  end
end
