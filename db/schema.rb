# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_03_05_090241) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "email"
    t.string "phone"
    t.string "status", default: "pending"
    t.string "password_digest"
    t.string "otp_pin"
    t.datetime "otp_sent_at"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "deleted_at"
    t.string "gender"
    t.string "provider"
    t.string "provider_uid"
    t.boolean "google_signup", default: false
    t.string "country_code", default: "+91"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_accounts_on_email", unique: true
    t.index ["phone"], name: "index_accounts_on_phone", unique: true
  end

  create_table "addresses", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name"
    t.string "address_line1", null: false
    t.string "address_line2"
    t.string "city", null: false
    t.string "state", null: false
    t.string "country", default: "India", null: false
    t.string "postal_code", null: false
    t.string "phone"
    t.integer "address_type", default: 0
    t.boolean "is_default", default: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_addresses_on_account_id"
  end

  create_table "admin_roles", force: :cascade do |t|
    t.integer "admin_user_id", null: false
    t.integer "role_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id", "role_id"], name: "index_admin_roles_on_admin_user_id_and_role_id", unique: true
    t.index ["admin_user_id"], name: "index_admin_roles_on_admin_user_id"
    t.index ["role_id"], name: "index_admin_roles_on_role_id"
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "email"
    t.string "phone"
    t.string "country_code", default: "+91"
    t.string "status", default: "active"
    t.string "password_digest"
    t.string "otp_pin"
    t.datetime "otp_sent_at"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "deleted_at"
    t.datetime "last_login_at"
    t.boolean "is_super_admin", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["is_super_admin"], name: "index_admin_users_on_is_super_admin"
    t.index ["phone"], name: "index_admin_users_on_phone", unique: true
  end

  create_table "brands", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.boolean "is_active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "cart_items", force: :cascade do |t|
    t.integer "cart_id", null: false
    t.integer "dealer_product_id", null: false
    t.integer "quantity"
    t.decimal "total_price", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cart_id", "dealer_product_id"], name: "index_cart_items_uniqueness", unique: true
    t.index ["cart_id"], name: "index_cart_items_on_cart_id"
    t.index ["dealer_product_id"], name: "index_cart_items_on_dealer_product_id"
  end

  create_table "carts", force: :cascade do |t|
    t.string "buyer_type", null: false
    t.integer "buyer_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["buyer_type", "buyer_id"], name: "index_carts_on_buyer"
    t.index ["buyer_type", "buyer_id"], name: "index_carts_on_buyer_type_and_buyer_id", unique: true
  end

  create_table "cat_filters", force: :cascade do |t|
    t.string "name"
    t.string "data_type"
    t.boolean "is_filterable", default: true
    t.integer "category_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_cat_filters_on_category_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.boolean "is_active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "contact_us", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dealer_locations", force: :cascade do |t|
    t.integer "dealer_id"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.integer "service_radius_km", default: 5
    t.boolean "is_active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dealer_id"], name: "index_dealer_locations_on_dealer_id"
  end

  create_table "dealer_products", force: :cascade do |t|
    t.integer "dealer_id", null: false
    t.integer "product_id", null: false
    t.integer "product_variant_id", null: false
    t.integer "stock_quantity"
    t.boolean "is_active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "approve_status", default: 0
    t.index ["approve_status"], name: "index_dealer_products_on_approve_status"
    t.index ["dealer_id"], name: "index_dealer_products_on_dealer_id"
    t.index ["product_id"], name: "index_dealer_products_on_product_id"
    t.index ["product_variant_id"], name: "index_dealer_products_on_product_variant_id"
  end

  create_table "dealer_profiles", force: :cascade do |t|
    t.integer "dealer_id", null: false
    t.string "business_name"
    t.string "business_type"
    t.string "gst_number"
    t.string "pan_number"
    t.string "aadhar_number"
    t.string "bank_name"
    t.string "bank_account_number"
    t.string "ifsc_code"
    t.text "business_address"
    t.string "business_contact_number"
    t.string "business_email"
    t.boolean "is_verified", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dealer_id"], name: "index_dealer_profiles_on_dealer_id"
  end

  create_table "dealers", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "email"
    t.string "phone"
    t.string "status", default: "pending"
    t.string "password_digest"
    t.string "otp_pin"
    t.datetime "otp_sent_at"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "deleted_at"
    t.string "gender"
    t.string "country_code", default: "+91"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_dealers_on_email", unique: true
    t.index ["phone"], name: "index_dealers_on_phone", unique: true
  end

  create_table "product_specifications", force: :cascade do |t|
    t.integer "product_id", null: false
    t.string "key"
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_product_specifications_on_product_id"
  end

  create_table "product_variants", force: :cascade do |t|
    t.integer "product_id", null: false
    t.string "variant_sku"
    t.decimal "price", precision: 10, scale: 2, null: false
    t.decimal "selling_price", precision: 10, scale: 2
    t.decimal "dealer_price", precision: 10, scale: 2, null: false
    t.decimal "dealer_selling_price", precision: 10, scale: 2
    t.integer "discount_percentage", default: 0
    t.boolean "is_active", default: true
    t.string "variant_attributes", default: "{}"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_product_variants_on_product_id"
    t.index ["variant_sku"], name: "index_product_variants_on_variant_sku", unique: true
  end

  create_table "products", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.string "sku"
    t.text "desc"
    t.string "material"
    t.string "features", default: "[]"
    t.string "care_instructions", default: "[]"
    t.integer "brand_id"
    t.boolean "is_featured", default: false
    t.boolean "is_new", default: false
    t.boolean "is_active", default: true
    t.integer "category_id", null: false
    t.decimal "tax_rate", precision: 5, scale: 2, default: "0.0", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id"], name: "index_products_on_brand_id"
    t.index ["category_id"], name: "index_products_on_category_id"
    t.index ["is_featured"], name: "index_products_on_is_featured"
    t.index ["sku"], name: "index_products_on_sku", unique: true
    t.index ["slug"], name: "index_products_on_slug", unique: true
  end

  create_table "reviews", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "dealer_product_id", null: false
    t.string "title"
    t.text "comment"
    t.integer "rating"
    t.boolean "verified"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_reviews_on_account_id"
    t.index ["dealer_product_id"], name: "index_reviews_on_dealer_product_id"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.string "module_access", default: "[]"
    t.boolean "is_active", default: true
    t.integer "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_roles_on_created_by_id"
  end

  create_table "wholesaler_posts", force: :cascade do |t|
    t.bigint "dealer_id", null: false
    t.bigint "dealer_product_id"
    t.string "title"
    t.text "body"
    t.decimal "price", precision: 12, scale: 2
    t.integer "stock_quantity", default: 0
    t.string "modal_no"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dealer_id"], name: "index_wholesaler_posts_on_dealer_id"
    t.index ["dealer_product_id"], name: "index_wholesaler_posts_on_dealer_product_id"
  end

  add_foreign_key "addresses", "accounts"
  add_foreign_key "admin_roles", "admin_users"
  add_foreign_key "admin_roles", "roles"
  add_foreign_key "cart_items", "carts"
  add_foreign_key "cart_items", "dealer_products"
  add_foreign_key "cat_filters", "categories"
  add_foreign_key "dealer_locations", "dealers"
  add_foreign_key "dealer_products", "dealers"
  add_foreign_key "dealer_products", "product_variants"
  add_foreign_key "dealer_products", "products"
  add_foreign_key "dealer_profiles", "dealers"
  add_foreign_key "product_specifications", "products"
  add_foreign_key "product_variants", "products"
  add_foreign_key "products", "brands"
  add_foreign_key "products", "categories"
  add_foreign_key "reviews", "accounts"
  add_foreign_key "reviews", "dealer_products"
  add_foreign_key "roles", "admin_users", column: "created_by_id"
  add_foreign_key "wholesaler_posts", "dealer_products"
  add_foreign_key "wholesaler_posts", "dealers"
end
