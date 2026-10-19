Rails.application.routes.draw do
  resource :session, only: %i[ new create destroy ]
  resource :registration, only: %i[ new create ]
  resource :approval, only: :show
  resource :password, only: %i[ edit update ]
  resources :friendships, only: %i[ index create update destroy ]

  namespace :admin do
    root "dashboards#show"
    resources :users, only: :index do
      scope module: :users do
        resource :approval, only: %i[ create destroy ]
        resource :rejection, only: :create
        resource :block, only: %i[ create destroy ]
        resource :password, only: %i[ edit update ]
      end
    end
  end

  resources :practice_tables, only: :create
  resources :tables, only: :show do
    resource :departure, only: :create, module: :tables
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "home#show"
end
