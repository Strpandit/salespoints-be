Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  namespace :api do
    namespace :admin do
      resources :orders, only: [:index, :show] do
        member do
          get :download_invoice
        end
      end
    end
    resources :accounts do
      put :change_password, on: :member
      patch :block, on: :member
      patch :unblock, on: :member
      resources :addresses
    end

    post 'otp/send', to: 'auth#send_otp'
    post 'otp/verify', to: 'auth#verify_otp'

    post 'auth/google',  to: 'auth#google_login'
    post 'password', to: 'passwords#create'
    post 'set_password', to: 'passwords#update'

    resources :orders, only: [:index, :show, :update] do
      collection do
        post :buy_now
      end
      member do
        post :refund
        post :release_settlement
        get :download_invoice
      end

      resources :return_requests, only: [:index, :create, :update]
    end
    resources :delivery_confirmations, only: [:show], param: :token do
      member do
        post :submit
        post :resend_otps
        post :verify_otps
      end
    end
    resources :notifications, only: [:index] do
      collection do
        get :unread_count
        patch :mark_all_read
      end
      member do
        patch :mark_read
      end
    end
    resources :dealer_ledger_entries, only: [:index]
    resources :dealer_payouts, only: [:index, :create, :update]
    get "payments/cashfree/verify", to: "payments#verify_cashfree"
    post "payments/cashfree/cancel", to: "payments#cancel_cashfree"
    post "payments/cashfree/webhook", to: "payments#cashfree_webhook"
    get "payments/:token", to: "payments#payment_details"
    get "whatsapp/webhook", to: "whatsapp_webhooks#verify"
    post "whatsapp/webhook", to: "whatsapp_webhooks#receive"

    # Admin routes
    resources :admin_users do
      patch :approve, on: :member
      post :assign_pincodes, on: :member
      get :admin_pincodes, on: :member
      delete :remove_pincode, on: :member
    end
    post "admin/login", to: "admin_users#login"
    post "admin/login_otp", to: "admin_users#login_otp"
    post "admin/forgot_password", to: "admin_users#forgot_password"
    post "admin/otp_confirmation", to: "admin_users#otp_confirmation"
    post "admin/verify_otp", to: "admin_users#verify_otp"
    post "admin/resend_signup_otp", to: "admin_users#resend_signup_otp"
    post "admin/reset_password", to: "admin_users#reset_user_password"
    put "admin/change_password", to: "admin_users#change_password"
    put "admin/:id/deactivate", to: "admin_users#deactivate"
    put "admin/:id/reactivate", to: "admin_users#reactivate"

    #roles and permissions
    resources :roles
    get "modules", to: "roles#modules"
    put "roles/:id/deactivate", to: "roles#deactivate"
    put "roles/:id/reactivate", to: "roles#reactivate"
    get "active_roles", to: "roles#active_roles"
    post "assign_role", to: "admin_roles#assign_role"

    # Categories and Filters
    resources :categories
    resources :cat_filters
    put "categories/:id/deactivate", to: "categories#deactivate"
    put "categories/:id/reactivate", to: "categories#reactivate"
    get "all_categories", to: "categories#all_categories"
    get "active_filters", to: "cat_filters#active_filters"

    #brands
    resources :brands
    get "all_brands", to: "brands#all_brands"
    put "brands/:id/deactivate", to: "brands#deactivate"
    put "brands/:id/reactivate", to: "brands#reactivate"

    #products
    resources :products do
      get :similar_product, on: :collection
      resources :reviews, only: [:index, :create]
    end
    get "active_products", to: "products#active_products"

    #Reviews
    resources :reviews

    #Deletion Requests
    resources :deletion_requests, only: [:create, :index] do
      member do
        patch :approve
        patch :reject
        delete :cancel
      end
    end

    # Dealers routes
    resources :dealers do
      get :active_dealers, on: :collection
      get :nearby, on: :collection
      get :admin_overview, on: :member
      patch :block, on: :member
      patch :unblock, on: :member
      patch :approve, on: :member
      patch :reject, on: :member
    end
    post "dealer/verify_otp", to: "dealers#verify_otp"
    post "dealer/resend_signup_otp", to: "dealers#resend_signup_otp"
    # Dealer and dealer products
    post "dealer/login", to: "dealer_sessions#login"
    post 'dealer/change_password', to: 'dealer_sessions#change_password'
    post "dealer/forgot_password", to: "dealer_sessions#forgot_password"
    post "dealer/otp_confirmation", to: "dealer_sessions#otp_confirmation"
    post "dealer/reset_password", to: "dealer_sessions#reset_password"
    resources :dealer_addresses, path: "dealer/addresses", only: [:index, :create, :show, :update, :destroy]

    resources :dealer_products do
      patch :approve, on: :member
      patch :reject, on: :member
      patch :revert_to_pending, on: :member
      patch :update_stock, on: :member
      patch :toggle_active, on: :member
      collection do
        get :shop_index
        get :similar
        get :b2b_shop_index
        get :b2b_show
        get :b2b_similar
        get :check_pincode
        get :check_b2b_pincode
        get :b2b_search_suggestions
      end
      resources :reviews, only: [:index, :create]
    end
    resources :b2b_orders, only: [:index, :show] do
      collection do
        post :place_direct
        post :payment
      end
      member do
        post :accept
        post :reject
        patch :update_status
        get :download_invoice
      end
    end
    resources :dealer_notifications, only: [:index] do
      member do
        patch :mark_read
      end
    end

    # Dealer bulk upload (CSV) - dealers can bulk upload their inventory mapping to existing variants
    post "dealer/bulk_upload", to: "dealer_bulk_uploads#create"

    # Wholesaler posts (facebook-like posts by dealers) and quick buy endpoint
    resources :wholesaler_posts do
      collection do
        get :pending
      end

      member do
        patch :approve
        patch :reject
        patch :toggle_status
        post :reupload
        post :buy
        post :rate
      end
    end

    # Generic bulk uploads for admins (brands, categories, cat_filters, roles, products)
    post "bulk_uploads", to: "bulk_uploads#create"

    # Dealer coupons
    resources :coupons

    # Analytics and Reports
    get 'analytics/dashboard', to: 'analytics#dashboard'
    get 'analytics/revenue', to: 'analytics#revenue'
    get 'analytics/orders', to: 'analytics#orders'
    get 'analytics/payments', to: 'analytics#payments'
    get 'analytics/sellers', to: 'analytics#sellers'
    get 'analytics/products', to: 'analytics#products'
    get 'analytics/customers', to: 'analytics#customers'
    get 'analytics/real_time', to: 'analytics#real_time'

    get 'reports/list', to: 'reports#list'
    post 'reports/generate', to: 'reports#generate'
    get 'reports/download/:filename', to: 'reports#download'
    post 'reports/schedule', to: 'reports#schedule'

    # Support Tickets
    post 'support_tickets', to: 'support_tickets#create'
    get 'support_tickets', to: 'support_tickets#index'
    get 'support_tickets/:id', to: 'support_tickets#show'
    patch 'support_tickets/:id', to: 'support_tickets#update'
    post 'support_tickets/:id/messages', to: 'support_tickets#add_message'
    post 'support_tickets/:id/assign', to: 'support_tickets#assign'
    post 'support_tickets/:id/resolve', to: 'support_tickets#resolve'
    post 'support_tickets/:id/close', to: 'support_tickets#close'
    get 'support_tickets_statistics', to: 'support_tickets#statistics'

    # Contact Form
    post 'contact_forms', to: 'contact_forms#create'
    get 'contact_forms', to: 'contact_forms#index'
    get 'contact_forms/:id', to: 'contact_forms#show'
    post 'contact_forms/:id/respond', to: 'contact_forms#respond'

  end

end
