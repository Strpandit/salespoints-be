# db/migrate/xxxxxx_fix_all_unique_indexes_for_soft_delete.rb
class FixAllUniqueIndexesForSoftDelete < ActiveRecord::Migration[8.0]
  def up
    # ============ DEALERS TABLE ============
    remove_index :dealers, name: 'index_dealers_on_email' if index_exists?(:dealers, :email, name: 'index_dealers_on_email')
    remove_index :dealers, name: 'index_dealers_on_phone' if index_exists?(:dealers, :phone, name: 'index_dealers_on_phone')
    remove_index :dealers, name: 'index_dealers_on_dealer_code' if index_exists?(:dealers, :dealer_code, name: 'index_dealers_on_dealer_code')
    
    add_index :dealers, :email, unique: true, name: 'index_dealers_on_email', where: 'deleted_at IS NULL'
    add_index :dealers, :phone, unique: true, name: 'index_dealers_on_phone', where: 'deleted_at IS NULL'
    add_index :dealers, :dealer_code, unique: true, name: 'index_dealers_on_dealer_code', where: 'deleted_at IS NULL'
    
    # ============ ACCOUNTS TABLE ============
    remove_index :accounts, name: 'index_accounts_on_email' if index_exists?(:accounts, :email, name: 'index_accounts_on_email')
    remove_index :accounts, name: 'index_accounts_on_phone' if index_exists?(:accounts, :phone, name: 'index_accounts_on_phone')
    
    add_index :accounts, :email, unique: true, name: 'index_accounts_on_email', where: 'deleted_at IS NULL'
    add_index :accounts, :phone, unique: true, name: 'index_accounts_on_phone', where: 'deleted_at IS NULL'
    
    # ============ ADMIN_USERS TABLE ============
    remove_index :admin_users, name: 'index_admin_users_on_email' if index_exists?(:admin_users, :email, name: 'index_admin_users_on_email')
    remove_index :admin_users, name: 'index_admin_users_on_phone' if index_exists?(:admin_users, :phone, name: 'index_admin_users_on_phone')
    
    add_index :admin_users, :email, unique: true, name: 'index_admin_users_on_email', where: 'deleted_at IS NULL'
    add_index :admin_users, :phone, unique: true, name: 'index_admin_users_on_phone', where: 'deleted_at IS NULL'
    
    # ============ PRODUCTS TABLE ============
    if index_exists?(:products, :sku, name: 'index_products_on_sku')
      remove_index :products, name: 'index_products_on_sku'
      add_index :products, :sku, unique: true, name: 'index_products_on_sku', where: 'deleted_at IS NULL'
    end
    
    if index_exists?(:products, :slug, name: 'index_products_on_slug')
      remove_index :products, name: 'index_products_on_slug'
      add_index :products, :slug, unique: true, name: 'index_products_on_slug', where: 'deleted_at IS NULL'
    end
    
    # ============ PRODUCT_VARIANTS TABLE ============
    if index_exists?(:product_variants, :variant_sku, name: 'index_product_variants_on_variant_sku')
      remove_index :product_variants, name: 'index_product_variants_on_variant_sku'
      add_index :product_variants, :variant_sku, unique: true, name: 'index_product_variants_on_variant_sku', where: 'deleted_at IS NULL'
    end
    
    # ============ CATEGORIES TABLE (if has deleted_at) ============
    if table_exists?(:categories) && column_exists?(:categories, :deleted_at)
      if index_exists?(:categories, :slug, name: 'index_categories_on_slug')
        remove_index :categories, name: 'index_categories_on_slug'
        add_index :categories, :slug, unique: true, name: 'index_categories_on_slug', where: 'deleted_at IS NULL'
      end
    end
    
    # ============ BRANDS TABLE (if has deleted_at) ============
    if table_exists?(:brands) && column_exists?(:brands, :deleted_at)
      if index_exists?(:brands, :slug, name: 'index_brands_on_slug')
        remove_index :brands, name: 'index_brands_on_slug'
        add_index :brands, :slug, unique: true, name: 'index_brands_on_slug', where: 'deleted_at IS NULL'
      end
    end
    
    # ============ ROLES TABLE (if has deleted_at) ============
    if table_exists?(:roles) && column_exists?(:roles, :deleted_at)
      if index_exists?(:roles, :name, name: 'index_roles_on_name')
        remove_index :roles, name: 'index_roles_on_name'
        add_index :roles, :name, unique: true, name: 'index_roles_on_name', where: 'deleted_at IS NULL'
      end
    end
    
    # ============ B2B_ORDER_OFFERS TABLE ============
    if index_exists?(:b2b_order_offers, :accept_token, name: 'index_b2b_order_offers_on_accept_token')
      remove_index :b2b_order_offers, name: 'index_b2b_order_offers_on_accept_token'
      add_index :b2b_order_offers, :accept_token, unique: true, name: 'index_b2b_order_offers_on_accept_token'
    end
    
    if index_exists?(:b2b_order_offers, :reject_token, name: 'index_b2b_order_offers_on_reject_token')
      remove_index :b2b_order_offers, name: 'index_b2b_order_offers_on_reject_token'
      add_index :b2b_order_offers, :reject_token, unique: true, name: 'index_b2b_order_offers_on_reject_token'
    end
    
    # ============ COUPONS TABLE ============
    if index_exists?(:coupons, :code, name: 'index_coupons_on_code')
      remove_index :coupons, name: 'index_coupons_on_code'
      add_index :coupons, :code, unique: true, name: 'index_coupons_on_code'
    end
    
    # ============ DEALER_LEDGER_ENTRIES TABLE ============
    if index_exists?(:dealer_ledger_entries, :reference_code, name: 'index_dealer_ledger_entries_on_reference_code')
      remove_index :dealer_ledger_entries, name: 'index_dealer_ledger_entries_on_reference_code'
      add_index :dealer_ledger_entries, :reference_code, unique: true, name: 'index_dealer_ledger_entries_on_reference_code'
    end
    
    # ============ DEALER_PAYOUTS TABLE ============
    if index_exists?(:dealer_payouts, :request_number, name: 'index_dealer_payouts_on_request_number')
      remove_index :dealer_payouts, name: 'index_dealer_payouts_on_request_number'
      add_index :dealer_payouts, :request_number, unique: true, name: 'index_dealer_payouts_on_request_number'
    end
    
    # ============ ORDERS TABLE ============
    if index_exists?(:orders, :order_number, name: 'index_orders_on_order_number')
      remove_index :orders, name: 'index_orders_on_order_number'
      add_index :orders, :order_number, unique: true, name: 'index_orders_on_order_number'
    end
    
    # ============ PAYMENT_ATTEMPTS TABLE ============
    if index_exists?(:payment_attempts, :attempt_number, name: 'index_payment_attempts_on_attempt_number')
      remove_index :payment_attempts, name: 'index_payment_attempts_on_attempt_number'
      add_index :payment_attempts, :attempt_number, unique: true, name: 'index_payment_attempts_on_attempt_number'
    end
    
    # ============ PAYMENT_GATEWAY_WEBHOOK_EVENTS TABLE ============
    if index_exists?(:payment_gateway_webhook_events, :provider, name: 'idx_pg_webhook_events_unique')
      remove_index :payment_gateway_webhook_events, name: 'idx_pg_webhook_events_unique'
      add_index :payment_gateway_webhook_events, [:provider, :event_id], unique: true, name: 'idx_pg_webhook_events_unique'
    end
    
    # ============ PUSH_SUBSCRIPTIONS TABLE ============
    if index_exists?(:push_subscriptions, :token, name: 'index_push_subscriptions_on_token')
      remove_index :push_subscriptions, name: 'index_push_subscriptions_on_token'
      add_index :push_subscriptions, :token, unique: true, name: 'index_push_subscriptions_on_token'
    end
    
    # ============ WHATSAPP_WEBHOOK_EVENTS TABLE ============
    if index_exists?(:whatsapp_webhook_events, :event_key, name: 'index_whatsapp_webhook_events_on_event_key')
      remove_index :whatsapp_webhook_events, name: 'index_whatsapp_webhook_events_on_event_key'
      add_index :whatsapp_webhook_events, :event_key, unique: true, name: 'index_whatsapp_webhook_events_on_event_key'
    end
    
    # ============ WHOLESALER_POST_RATINGS TABLE ============
    if index_exists?(:wholesaler_post_ratings, [:wholesaler_post_id, :dealer_id], name: 'idx_wholesaler_post_ratings_unique')
      remove_index :wholesaler_post_ratings, name: 'idx_wholesaler_post_ratings_unique'
      add_index :wholesaler_post_ratings, [:wholesaler_post_id, :dealer_id], unique: true, name: 'idx_wholesaler_post_ratings_unique'
    end
    
    # ============ ADMIN_ROLES TABLE ============
    if index_exists?(:admin_roles, [:admin_user_id, :role_id], name: 'index_admin_roles_on_admin_user_id_and_role_id')
      remove_index :admin_roles, name: 'index_admin_roles_on_admin_user_id_and_role_id'
      add_index :admin_roles, [:admin_user_id, :role_id], unique: true, name: 'index_admin_roles_on_admin_user_id_and_role_id'
    end
    
    # ============ COUPON_USAGES TABLE ============
    if index_exists?(:coupon_usages, :coupon_id, name: 'idx_coupon_usages_unique')
      remove_index :coupon_usages, name: 'idx_coupon_usages_unique'
      add_index :coupon_usages, [:coupon_id, :user_type, :user_id], unique: true, name: 'idx_coupon_usages_unique'
    end
    
    # ============ BRAND_CATEGORIES TABLE ============
    if index_exists?(:brand_categories, [:brand_id, :category_id], name: 'index_brand_categories_on_brand_id_and_category_id')
      remove_index :brand_categories, name: 'index_brand_categories_on_brand_id_and_category_id'
      add_index :brand_categories, [:brand_id, :category_id], unique: true, name: 'index_brand_categories_on_brand_id_and_category_id'
    end
  end

  def down
    # ============ DEALERS ============
    remove_index :dealers, name: 'index_dealers_on_email' if index_exists?(:dealers, :email, name: 'index_dealers_on_email')
    remove_index :dealers, name: 'index_dealers_on_phone' if index_exists?(:dealers, :phone, name: 'index_dealers_on_phone')
    remove_index :dealers, name: 'index_dealers_on_dealer_code' if index_exists?(:dealers, :dealer_code, name: 'index_dealers_on_dealer_code')
    
    add_index :dealers, :email, unique: true, name: 'index_dealers_on_email'
    add_index :dealers, :phone, unique: true, name: 'index_dealers_on_phone'
    add_index :dealers, :dealer_code, unique: true, name: 'index_dealers_on_dealer_code'
    
    # ============ ACCOUNTS ============
    remove_index :accounts, name: 'index_accounts_on_email' if index_exists?(:accounts, :email, name: 'index_accounts_on_email')
    remove_index :accounts, name: 'index_accounts_on_phone' if index_exists?(:accounts, :phone, name: 'index_accounts_on_phone')
    
    add_index :accounts, :email, unique: true, name: 'index_accounts_on_email'
    add_index :accounts, :phone, unique: true, name: 'index_accounts_on_phone'
    
    # ============ ADMIN_USERS ============
    remove_index :admin_users, name: 'index_admin_users_on_email' if index_exists?(:admin_users, :email, name: 'index_admin_users_on_email')
    remove_index :admin_users, name: 'index_admin_users_on_phone' if index_exists?(:admin_users, :phone, name: 'index_admin_users_on_phone')
    
    add_index :admin_users, :email, unique: true, name: 'index_admin_users_on_email'
    add_index :admin_users, :phone, unique: true, name: 'index_admin_users_on_phone'
    
    # ============ PRODUCTS ============
    remove_index :products, name: 'index_products_on_sku' if index_exists?(:products, :sku, name: 'index_products_on_sku')
    remove_index :products, name: 'index_products_on_slug' if index_exists?(:products, :slug, name: 'index_products_on_slug')
    
    add_index :products, :sku, unique: true, name: 'index_products_on_sku'
    add_index :products, :slug, unique: true, name: 'index_products_on_slug'
    
    # ============ PRODUCT_VARIANTS ============
    remove_index :product_variants, name: 'index_product_variants_on_variant_sku' if index_exists?(:product_variants, :variant_sku, name: 'index_product_variants_on_variant_sku')
    add_index :product_variants, :variant_sku, unique: true, name: 'index_product_variants_on_variant_sku'
    
    # ============ OTHERS (restore original) ============
    add_index :coupons, :code, unique: true, name: 'index_coupons_on_code' if !index_exists?(:coupons, :code, name: 'index_coupons_on_code')
    add_index :orders, :order_number, unique: true, name: 'index_orders_on_order_number' if !index_exists?(:orders, :order_number, name: 'index_orders_on_order_number')
    add_index :payment_attempts, :attempt_number, unique: true, name: 'index_payment_attempts_on_attempt_number' if !index_exists?(:payment_attempts, :attempt_number, name: 'index_payment_attempts_on_attempt_number')
  end
end