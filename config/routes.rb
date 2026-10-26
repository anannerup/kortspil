Rails.application.routes.draw do
  resource :session, only: %i[ new create destroy ]
  resource :registration, only: %i[ new create ]
  resource :approval, only: :show
  resource :password, only: %i[ edit update ]
  resource :password_reset_request, only: %i[ new create ]
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

  # A bord before its spil lives in memory (WaitingTable) at /borde/:id;
  # once the spil starts it is stored, at /tables/:id.
  resources :practice_tables, only: :create
  resources :waiting_tables, path: "borde", only: %i[ show create ] do
    scope module: :waiting_tables do
      resource :seat, only: :create
      resource :start, only: :create
      resource :departure, only: :create
      resource :kick, only: :create
      resource :bot, only: %i[ create update destroy ]
      resource :settings, only: :update
      resources :nudges, only: %i[ create update destroy ]
    end
  end
  # The rules of both games and how the bots play them, in plain Danish.
  get "regelbog", to: "regelbog#show", as: :regelbog

  resources :tables, only: :show do
    scope module: :tables do
      resource :departure, only: :create
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Error pages (config.exceptions_app = routes). via: :all because the
  # failed request may have been a POST or DELETE.
  %w[ 400 404 406 422 500 ].each do |code|
    match code, to: "errors#show", via: :all, defaults: { code: code }
  end

  root "home#show"
end
