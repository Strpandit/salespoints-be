class CreateCarts < ActiveRecord::Migration[8.0]
  def change
    create_table :carts do |t|
      t.references :buyer, polymorphic: true, null: false
      t.timestamps
    end
    add_index :carts, [:buyer_type, :buyer_id], unique: true, name: 'index_carts_on_buyer_type_and_buyer_id'
  end
end
