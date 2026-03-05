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
    resources :accounts do
      patch :block, on: :member
      patch :unblock, on: :member
      resources :addresses
    end

    post 'otp/send', to: 'auth#send_otp'
    post 'otp/verify', to: 'auth#verify_otp'

    # cart endpoints
    get 'cart', to: 'carts#show'
    resources :cart_items, only: [:create, :update, :destroy]
    post 'auth/google',  to: 'auth#google_login'
    post 'password', to: 'passwords#create'
    post 'set_password', to: 'passwords#update'

    # Admin routes
    resources :admin_users
    post "admin/login", to: "admin_users#login"
    post "admin/forgot_password", to: "admin_users#forgot_password"
    post "admin/otp_confirmation", to: "admin_users#otp_confirmation"
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

    # Dealers routes
    resources :dealers do
      get :active_dealers, on: :collection
      patch :block, on: :member
      patch :unblock, on: :member
      patch :approve, on: :member
      patch :reject, on: :member
    end
    # Dealer and dealer products
    post "dealer/login", to: "dealer_sessions#login"
    post 'dealer/change_password', to: 'dealer_sessions#change_password'
    post "dealer/forgot_password", to: "dealer_sessions#forgot_password"
    post "dealer/otp_confirmation", to: "dealer_sessions#otp_confirmation"
    post "dealer/reset_password", to: "dealer_sessions#reset_password"

    resources :dealer_products do
      patch :approve, on: :member
      patch :reject, on: :member
      patch :revert_to_pending, on: :member
      patch :update_stock, on: :member
      patch :toggle_active, on: :member
      collection do
        get :shop_index
        get :similar
      end
    end

    # Dealer bulk upload (CSV) - dealers can bulk upload their inventory mapping to existing variants
    post "dealer/bulk_upload", to: "dealer_bulk_uploads#create"

    # Wholesaler posts (facebook-like posts by dealers) and quick buy endpoint
    resources :wholesaler_posts, only: [:index, :create, :show] do
      post :buy, on: :member
    end

    # Generic bulk uploads for admins (brands, categories, cat_filters, roles, products)
    post "bulk_uploads", to: "bulk_uploads#create"

  end

end
