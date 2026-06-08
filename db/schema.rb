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

ActiveRecord::Schema[8.0].define(version: 2026_06_08_174135) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_deletion_requests", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "reviewed_by_admin_id"
    t.string "status", default: "pending", null: false
    t.text "reason"
    t.text "rejection_reason"
    t.datetime "requested_at", null: false
    t.datetime "reviewed_at"
    t.datetime "password_verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_account_deletion_requests_on_account_id_and_status"
    t.index ["account_id"], name: "index_account_deletion_requests_on_account_id"
    t.index ["reviewed_by_admin_id"], name: "index_account_deletion_requests_on_reviewed_by_admin_id"
    t.index ["status"], name: "index_account_deletion_requests_on_status"
  end

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

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
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

  create_table "admin_deletion_requests", force: :cascade do |t|
    t.bigint "admin_user_id", null: false
    t.bigint "reviewed_by_admin_id"
    t.string "status", default: "pending", null: false
    t.text "reason"
    t.text "rejection_reason"
    t.datetime "requested_at", null: false
    t.datetime "reviewed_at"
    t.datetime "password_verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id", "status"], name: "index_admin_deletion_requests_on_admin_user_id_and_status"
    t.index ["admin_user_id"], name: "index_admin_deletion_requests_on_admin_user_id"
    t.index ["reviewed_by_admin_id"], name: "index_admin_deletion_requests_on_reviewed_by_admin_id"
    t.index ["status"], name: "index_admin_deletion_requests_on_status"
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
    t.string "alternate_phone"
    t.text "address"
    t.string "aadhar_number"
    t.string "pan_number"
    t.string "bank_name"
    t.string "bank_account_number"
    t.string "ifsc_code"
    t.string "account_holder_name"
    t.string "tenth_school_name"
    t.string "tenth_board"
    t.string "tenth_passing_year"
    t.string "tenth_percentage"
    t.string "twelfth_school_name"
    t.string "twelfth_board"
    t.string "twelfth_passing_year"
    t.string "twelfth_percentage"
    t.string "approval_status", default: "pending", null: false
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.decimal "salary", precision: 15, scale: 2
    t.index ["approval_status"], name: "index_admin_users_on_approval_status"
    t.index ["approved_by_id"], name: "index_admin_users_on_approved_by_id"
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["is_super_admin"], name: "index_admin_users_on_is_super_admin"
    t.index ["phone"], name: "index_admin_users_on_phone", unique: true
  end

  create_table "b2b_order_items", force: :cascade do |t|
    t.bigint "b2b_order_id", null: false
    t.bigint "dealer_product_id"
    t.bigint "product_variant_id", null: false
    t.integer "quantity", default: 1, null: false
    t.decimal "unit_price", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_price", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "open", null: false
    t.datetime "responded_at"
    t.index ["b2b_order_id"], name: "index_b2b_order_items_on_b2b_order_id"
    t.index ["dealer_product_id"], name: "index_b2b_order_items_on_dealer_product_id"
    t.index ["product_variant_id"], name: "index_b2b_order_items_on_product_variant_id"
    t.index ["status"], name: "index_b2b_order_items_on_status"
  end

  create_table "b2b_order_offers", force: :cascade do |t|
    t.bigint "b2b_order_id", null: false
    t.bigint "dealer_id", null: false
    t.bigint "notification_id"
    t.string "status", default: "open", null: false
    t.string "delivery_channel", default: "whatsapp", null: false
    t.jsonb "item_ids", default: [], null: false
    t.jsonb "delivery_payload", default: {}, null: false
    t.string "accept_token", null: false
    t.string "reject_token", null: false
    t.string "recipient_phone"
    t.string "whatsapp_message_id"
    t.string "whatsapp_status", default: "pending", null: false
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "read_at"
    t.datetime "failed_at"
    t.datetime "responded_at"
    t.datetime "expires_at"
    t.integer "rebroadcast_count", default: 0, null: false
    t.text "failure_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accept_token"], name: "index_b2b_order_offers_on_accept_token", unique: true
    t.index ["b2b_order_id", "dealer_id"], name: "index_b2b_order_offers_on_b2b_order_id_and_dealer_id"
    t.index ["b2b_order_id"], name: "index_b2b_order_offers_on_b2b_order_id"
    t.index ["dealer_id"], name: "index_b2b_order_offers_on_dealer_id"
    t.index ["notification_id"], name: "index_b2b_order_offers_on_notification_id"
    t.index ["reject_token"], name: "index_b2b_order_offers_on_reject_token", unique: true
    t.index ["status"], name: "index_b2b_order_offers_on_status"
    t.index ["whatsapp_status"], name: "index_b2b_order_offers_on_whatsapp_status"
  end

  create_table "b2b_orders", force: :cascade do |t|
    t.bigint "buyer_dealer_id", null: false
    t.bigint "seller_dealer_id"
    t.string "status", default: "pending", null: false
    t.decimal "subtotal_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "tax_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "discount_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "coupon_code"
    t.integer "requested_radius_km", default: 5, null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.datetime "accepted_at"
    t.datetime "cancelled_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "payment_method", default: "cod", null: false
    t.string "payment_status", default: "pending", null: false
    t.bigint "buyer_payment_attempt_id"
    t.datetime "last_rebroadcast_at"
    t.index ["buyer_dealer_id"], name: "index_b2b_orders_on_buyer_dealer_id"
    t.index ["buyer_payment_attempt_id"], name: "index_b2b_orders_on_buyer_payment_attempt_id"
    t.index ["payment_method"], name: "index_b2b_orders_on_payment_method"
    t.index ["payment_status"], name: "index_b2b_orders_on_payment_status"
    t.index ["seller_dealer_id"], name: "index_b2b_orders_on_seller_dealer_id"
    t.index ["status"], name: "index_b2b_orders_on_status"
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
    t.bigint "product_variant_id", null: false
    t.decimal "unit_price", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["cart_id", "dealer_product_id", "product_variant_id"], name: "index_cart_items_unique", unique: true
    t.index ["cart_id"], name: "index_cart_items_on_cart_id"
    t.index ["dealer_product_id"], name: "index_cart_items_on_dealer_product_id"
    t.index ["product_variant_id"], name: "index_cart_items_on_product_variant_id"
  end

  create_table "carts", force: :cascade do |t|
    t.string "buyer_type", null: false
    t.integer "buyer_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "coupon_id"
    t.string "coupon_code"
    t.index ["buyer_type", "buyer_id"], name: "index_carts_on_buyer"
    t.index ["buyer_type", "buyer_id"], name: "index_carts_on_buyer_type_and_buyer_id", unique: true
    t.index ["coupon_id"], name: "index_carts_on_coupon_id"
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

  create_table "contact_form_submissions", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "phone"
    t.string "subject", null: false
    t.text "message", null: false
    t.string "status", default: "received"
    t.text "admin_response"
    t.bigint "admin_user_id"
    t.datetime "responded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_contact_form_submissions_on_admin_user_id"
    t.index ["email"], name: "index_contact_form_submissions_on_email"
    t.index ["status"], name: "index_contact_form_submissions_on_status"
  end

  create_table "contact_us", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "coupon_usages", force: :cascade do |t|
    t.bigint "coupon_id", null: false
    t.string "user_type", null: false
    t.bigint "user_id", null: false
    t.integer "uses_count", default: 0, null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["coupon_id", "user_type", "user_id"], name: "idx_coupon_usages_unique", unique: true
    t.index ["coupon_id"], name: "index_coupon_usages_on_coupon_id"
  end

  create_table "coupons", force: :cascade do |t|
    t.string "code", null: false
    t.string "title"
    t.text "description"
    t.bigint "created_by_dealer_id"
    t.string "audience", default: "customer", null: false
    t.string "discount_type", default: "percentage", null: false
    t.decimal "discount_value", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "max_discount", precision: 10, scale: 2
    t.decimal "min_cart_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "max_uses"
    t.integer "used_count", default: 0, null: false
    t.integer "per_user_limit", default: 1, null: false
    t.datetime "starts_at"
    t.datetime "expires_at"
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["audience"], name: "index_coupons_on_audience"
    t.index ["code"], name: "index_coupons_on_code", unique: true
    t.index ["created_by_dealer_id"], name: "index_coupons_on_created_by_dealer_id"
  end

  create_table "dealer_deletion_requests", force: :cascade do |t|
    t.bigint "dealer_id", null: false
    t.bigint "reviewed_by_admin_id"
    t.string "status", default: "pending", null: false
    t.text "reason"
    t.text "rejection_reason"
    t.datetime "requested_at", null: false
    t.datetime "reviewed_at"
    t.datetime "password_verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dealer_id", "status"], name: "index_dealer_deletion_requests_on_dealer_id_and_status"
    t.index ["dealer_id"], name: "index_dealer_deletion_requests_on_dealer_id"
    t.index ["reviewed_by_admin_id"], name: "index_dealer_deletion_requests_on_reviewed_by_admin_id"
    t.index ["status"], name: "index_dealer_deletion_requests_on_status"
  end

  create_table "dealer_ledger_entries", force: :cascade do |t|
    t.bigint "dealer_id", null: false
    t.bigint "order_id"
    t.bigint "return_request_id"
    t.string "entry_type", null: false
    t.string "direction", null: false
    t.decimal "amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "balance_after", precision: 14, scale: 2, default: "0.0", null: false
    t.string "reference_code"
    t.text "description"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dealer_id"], name: "index_dealer_ledger_entries_on_dealer_id"
    t.index ["entry_type"], name: "index_dealer_ledger_entries_on_entry_type"
    t.index ["order_id"], name: "index_dealer_ledger_entries_on_order_id"
    t.index ["reference_code"], name: "index_dealer_ledger_entries_on_reference_code", unique: true
    t.index ["return_request_id"], name: "index_dealer_ledger_entries_on_return_request_id"
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

  create_table "dealer_payouts", force: :cascade do |t|
    t.bigint "dealer_id", null: false
    t.string "request_number", null: false
    t.decimal "amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "status", default: "pending", null: false
    t.string "bank_name"
    t.string "bank_account_number"
    t.string "ifsc_code"
    t.string "account_holder_name"
    t.string "payment_reference"
    t.string "payment_mode"
    t.text "admin_note"
    t.datetime "approved_at"
    t.datetime "processing_at"
    t.datetime "paid_at"
    t.datetime "rejected_at"
    t.datetime "cancelled_at"
    t.bigint "approved_by_admin_id"
    t.bigint "processed_by_admin_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_admin_id"], name: "index_dealer_payouts_on_approved_by_admin_id"
    t.index ["dealer_id"], name: "index_dealer_payouts_on_dealer_id"
    t.index ["processed_by_admin_id"], name: "index_dealer_payouts_on_processed_by_admin_id"
    t.index ["request_number"], name: "index_dealer_payouts_on_request_number", unique: true
    t.index ["status"], name: "index_dealer_payouts_on_status"
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
    t.string "work_category"
    t.string "associated_brands"
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
    t.string "dealer_code", null: false
    t.decimal "settlement_balance", precision: 14, scale: 2, default: "0.0", null: false
    t.index ["dealer_code"], name: "index_dealers_on_dealer_code", unique: true
    t.index ["email"], name: "index_dealers_on_email", unique: true
    t.index ["phone"], name: "index_dealers_on_phone", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.string "receiver_type", null: false
    t.bigint "receiver_id", null: false
    t.string "actor_type"
    t.bigint "actor_id"
    t.string "notifiable_type"
    t.bigint "notifiable_id"
    t.string "notification_type", null: false
    t.string "title", null: false
    t.text "body"
    t.jsonb "payload", default: {}, null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "sent_at"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable"
    t.index ["read_at"], name: "index_notifications_on_read_at"
    t.index ["receiver_type", "receiver_id"], name: "index_notifications_on_receiver"
  end

  create_table "order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "dealer_product_id", null: false
    t.bigint "product_variant_id", null: false
    t.integer "quantity", default: 1, null: false
    t.decimal "unit_price", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_price", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dealer_product_id"], name: "index_order_items_on_dealer_product_id"
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_variant_id"], name: "index_order_items_on_product_variant_id"
  end

  create_table "orders", force: :cascade do |t|
    t.string "order_number", null: false
    t.string "buyer_type", null: false
    t.bigint "buyer_id", null: false
    t.bigint "seller_dealer_id"
    t.string "status", default: "pending", null: false
    t.decimal "subtotal_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "tax_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "discount_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "coupon_code"
    t.string "payment_method", default: "cod", null: false
    t.string "payment_status", default: "pending", null: false
    t.datetime "placed_at"
    t.jsonb "billing_address", default: {}, null: false
    t.jsonb "shipping_address", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "payment_gateway"
    t.string "gateway_order_reference"
    t.string "payment_session_id"
    t.string "payment_reference"
    t.jsonb "payment_gateway_payload", default: {}, null: false
    t.text "status_note"
    t.datetime "payment_confirmed_at"
    t.datetime "cancelled_at"
    t.datetime "delivered_at"
    t.datetime "shipped_at"
    t.datetime "processing_at"
    t.decimal "commission_rate", precision: 5, scale: 2, default: "10.0", null: false
    t.decimal "commission_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "marketplace_fee_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "seller_settlement_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "settlement_status", default: "on_hold", null: false
    t.datetime "settlement_due_at"
    t.datetime "settled_at"
    t.datetime "hold_released_at"
    t.string "refund_status", default: "none", null: false
    t.decimal "refund_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "refunded_at"
    t.text "refund_reason"
    t.datetime "return_window_closes_at"
    t.index ["buyer_type", "buyer_id"], name: "index_orders_on_buyer_type_and_buyer_id"
    t.index ["gateway_order_reference"], name: "index_orders_on_gateway_order_reference"
    t.index ["order_number"], name: "index_orders_on_order_number", unique: true
    t.index ["payment_reference"], name: "index_orders_on_payment_reference"
    t.index ["refund_status"], name: "index_orders_on_refund_status"
    t.index ["settlement_due_at"], name: "index_orders_on_settlement_due_at"
    t.index ["settlement_status"], name: "index_orders_on_settlement_status"
    t.index ["status"], name: "index_orders_on_status"
  end

  create_table "payment_attempts", force: :cascade do |t|
    t.string "attempt_number", null: false
    t.string "buyer_type", null: false
    t.bigint "buyer_id", null: false
    t.string "status", default: "pending", null: false
    t.decimal "amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "currency", default: "INR", null: false
    t.string "coupon_code"
    t.jsonb "billing_address", default: {}, null: false
    t.jsonb "shipping_address", default: {}, null: false
    t.jsonb "cart_snapshot", default: {}, null: false
    t.string "payment_gateway", default: "cashfree", null: false
    t.string "gateway_order_reference"
    t.string "payment_session_id"
    t.string "payment_reference"
    t.jsonb "payment_gateway_payload", default: {}, null: false
    t.text "failure_reason"
    t.datetime "paid_at"
    t.datetime "cancelled_at"
    t.datetime "failed_at"
    t.datetime "processed_at"
    t.jsonb "result_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["attempt_number"], name: "index_payment_attempts_on_attempt_number", unique: true
    t.index ["buyer_type", "buyer_id"], name: "index_payment_attempts_on_buyer_type_and_buyer_id"
    t.index ["gateway_order_reference"], name: "index_payment_attempts_on_gateway_order_reference"
    t.index ["payment_reference"], name: "index_payment_attempts_on_payment_reference"
    t.index ["status"], name: "index_payment_attempts_on_status"
  end

  create_table "payment_gateway_webhook_events", force: :cascade do |t|
    t.string "provider", null: false
    t.string "event_type"
    t.string "event_id", null: false
    t.string "payload_digest", null: false
    t.string "status", default: "received", null: false
    t.integer "response_code"
    t.datetime "received_at", null: false
    t.datetime "processed_at"
    t.jsonb "headers", default: {}, null: false
    t.jsonb "payload", default: {}, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "attempts", default: 0, null: false
    t.index ["provider", "event_id"], name: "idx_pg_webhook_events_unique", unique: true
    t.index ["received_at"], name: "index_payment_gateway_webhook_events_on_received_at"
    t.index ["status"], name: "index_payment_gateway_webhook_events_on_status"
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

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "subscriber_type", null: false
    t.bigint "subscriber_id", null: false
    t.string "token", null: false
    t.string "platform"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subscriber_type", "subscriber_id"], name: "index_push_subscriptions_on_subscriber"
    t.index ["token"], name: "index_push_subscriptions_on_token", unique: true
  end

  create_table "return_requests", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "requester_type", null: false
    t.bigint "requester_id", null: false
    t.string "request_type", null: false
    t.string "status", default: "requested", null: false
    t.text "reason"
    t.text "details"
    t.decimal "refund_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "seller_adjustment_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.text "resolution_notes"
    t.datetime "approved_at"
    t.datetime "received_at"
    t.datetime "completed_at"
    t.datetime "rejected_at"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_return_requests_on_order_id"
    t.index ["request_type"], name: "index_return_requests_on_request_type"
    t.index ["requester_type", "requester_id"], name: "index_return_requests_on_requester"
    t.index ["status"], name: "index_return_requests_on_status"
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
    t.text "module_access", default: "--- []\n"
    t.boolean "is_active", default: true
    t.integer "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "module_permissions", default: "--- {}\n"
    t.index ["created_by_id"], name: "index_roles_on_created_by_id"
  end

  create_table "support_tickets", force: :cascade do |t|
    t.string "ticket_number", null: false
    t.bigint "account_id"
    t.bigint "dealer_id"
    t.bigint "admin_user_id"
    t.string "user_type", null: false
    t.string "subject", null: false
    t.text "description", null: false
    t.string "category", null: false
    t.string "priority", default: "medium"
    t.string "status", default: "open"
    t.bigint "assigned_to_id"
    t.datetime "resolved_at"
    t.string "resolution_summary"
    t.integer "messages_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_support_tickets_on_account_id"
    t.index ["admin_user_id"], name: "index_support_tickets_on_admin_user_id"
    t.index ["assigned_to_id"], name: "index_support_tickets_on_assigned_to_id"
    t.index ["category"], name: "index_support_tickets_on_category"
    t.index ["dealer_id"], name: "index_support_tickets_on_dealer_id"
    t.index ["priority"], name: "index_support_tickets_on_priority"
    t.index ["status"], name: "index_support_tickets_on_status"
    t.index ["ticket_number"], name: "index_support_tickets_on_ticket_number"
    t.index ["user_type"], name: "index_support_tickets_on_user_type"
  end

  create_table "ticket_messages", force: :cascade do |t|
    t.bigint "support_ticket_id", null: false
    t.bigint "account_id"
    t.bigint "admin_user_id"
    t.string "sender_type", null: false
    t.text "message", null: false
    t.integer "attachments_count", default: 0
    t.boolean "is_internal", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "dealer_id"
    t.index ["account_id"], name: "index_ticket_messages_on_account_id"
    t.index ["admin_user_id"], name: "index_ticket_messages_on_admin_user_id"
    t.index ["created_at"], name: "index_ticket_messages_on_created_at"
    t.index ["dealer_id"], name: "index_ticket_messages_on_dealer_id"
    t.index ["support_ticket_id"], name: "index_ticket_messages_on_support_ticket_id"
  end

  create_table "whatsapp_webhook_events", force: :cascade do |t|
    t.string "provider", default: "meta", null: false
    t.string "event_type", null: false
    t.string "event_key", null: false
    t.string "direction", default: "inbound", null: false
    t.bigint "b2b_order_offer_id"
    t.bigint "notification_id"
    t.string "message_id"
    t.string "conversation_id"
    t.string "from_number"
    t.string "to_number"
    t.string "status"
    t.datetime "processed_at"
    t.jsonb "payload", default: {}, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["b2b_order_offer_id"], name: "index_whatsapp_webhook_events_on_b2b_order_offer_id"
    t.index ["event_key"], name: "index_whatsapp_webhook_events_on_event_key", unique: true
    t.index ["event_type"], name: "index_whatsapp_webhook_events_on_event_type"
    t.index ["message_id"], name: "index_whatsapp_webhook_events_on_message_id"
    t.index ["notification_id"], name: "index_whatsapp_webhook_events_on_notification_id"
    t.index ["status"], name: "index_whatsapp_webhook_events_on_status"
  end

  create_table "wholesaler_post_ratings", force: :cascade do |t|
    t.bigint "wholesaler_post_id", null: false
    t.bigint "dealer_id", null: false
    t.decimal "rating", precision: 3, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dealer_id"], name: "index_wholesaler_post_ratings_on_dealer_id"
    t.index ["wholesaler_post_id", "dealer_id"], name: "idx_wholesaler_post_ratings_unique", unique: true
    t.index ["wholesaler_post_id"], name: "index_wholesaler_post_ratings_on_wholesaler_post_id"
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
    t.decimal "rating", precision: 3, scale: 2, default: "0.0", null: false
    t.integer "rating_count", default: 0, null: false
    t.string "approve_status", default: "pending", null: false
    t.datetime "reviewed_at"
    t.text "rejection_reason"
    t.bigint "reviewed_by_admin_id"
    t.index ["approve_status"], name: "index_wholesaler_posts_on_approve_status"
    t.index ["dealer_id"], name: "index_wholesaler_posts_on_dealer_id"
    t.index ["dealer_product_id"], name: "index_wholesaler_posts_on_dealer_product_id"
    t.index ["reviewed_by_admin_id"], name: "index_wholesaler_posts_on_reviewed_by_admin_id"
  end

  add_foreign_key "account_deletion_requests", "accounts"
  add_foreign_key "account_deletion_requests", "admin_users", column: "reviewed_by_admin_id"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "addresses", "accounts"
  add_foreign_key "admin_deletion_requests", "admin_users"
  add_foreign_key "admin_deletion_requests", "admin_users", column: "reviewed_by_admin_id"
  add_foreign_key "admin_roles", "admin_users"
  add_foreign_key "admin_roles", "roles"
  add_foreign_key "admin_users", "admin_users", column: "approved_by_id"
  add_foreign_key "b2b_order_items", "b2b_orders"
  add_foreign_key "b2b_order_items", "dealer_products"
  add_foreign_key "b2b_order_items", "product_variants"
  add_foreign_key "b2b_order_offers", "b2b_orders"
  add_foreign_key "b2b_order_offers", "dealers"
  add_foreign_key "b2b_order_offers", "notifications"
  add_foreign_key "b2b_orders", "dealers", column: "buyer_dealer_id"
  add_foreign_key "b2b_orders", "dealers", column: "seller_dealer_id"
  add_foreign_key "b2b_orders", "payment_attempts", column: "buyer_payment_attempt_id"
  add_foreign_key "cart_items", "carts"
  add_foreign_key "cart_items", "dealer_products"
  add_foreign_key "cart_items", "product_variants"
  add_foreign_key "carts", "coupons"
  add_foreign_key "cat_filters", "categories"
  add_foreign_key "contact_form_submissions", "admin_users"
  add_foreign_key "coupon_usages", "coupons"
  add_foreign_key "coupons", "dealers", column: "created_by_dealer_id"
  add_foreign_key "dealer_deletion_requests", "admin_users", column: "reviewed_by_admin_id"
  add_foreign_key "dealer_deletion_requests", "dealers"
  add_foreign_key "dealer_ledger_entries", "dealers"
  add_foreign_key "dealer_ledger_entries", "orders"
  add_foreign_key "dealer_ledger_entries", "return_requests"
  add_foreign_key "dealer_locations", "dealers"
  add_foreign_key "dealer_payouts", "admin_users", column: "approved_by_admin_id"
  add_foreign_key "dealer_payouts", "admin_users", column: "processed_by_admin_id"
  add_foreign_key "dealer_payouts", "dealers"
  add_foreign_key "dealer_products", "dealers"
  add_foreign_key "dealer_products", "product_variants"
  add_foreign_key "dealer_products", "products"
  add_foreign_key "dealer_profiles", "dealers"
  add_foreign_key "order_items", "dealer_products"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "product_variants"
  add_foreign_key "orders", "dealers", column: "seller_dealer_id"
  add_foreign_key "product_specifications", "products"
  add_foreign_key "product_variants", "products"
  add_foreign_key "products", "brands"
  add_foreign_key "products", "categories"
  add_foreign_key "return_requests", "orders"
  add_foreign_key "reviews", "accounts"
  add_foreign_key "reviews", "dealer_products"
  add_foreign_key "roles", "admin_users", column: "created_by_id"
  add_foreign_key "support_tickets", "accounts"
  add_foreign_key "support_tickets", "admin_users"
  add_foreign_key "support_tickets", "admin_users", column: "assigned_to_id"
  add_foreign_key "support_tickets", "dealers"
  add_foreign_key "ticket_messages", "accounts"
  add_foreign_key "ticket_messages", "admin_users"
  add_foreign_key "ticket_messages", "dealers"
  add_foreign_key "ticket_messages", "support_tickets"
  add_foreign_key "whatsapp_webhook_events", "b2b_order_offers"
  add_foreign_key "whatsapp_webhook_events", "notifications"
  add_foreign_key "wholesaler_post_ratings", "dealers"
  add_foreign_key "wholesaler_post_ratings", "wholesaler_posts"
  add_foreign_key "wholesaler_posts", "admin_users", column: "reviewed_by_admin_id"
  add_foreign_key "wholesaler_posts", "dealer_products"
  add_foreign_key "wholesaler_posts", "dealers"
end
