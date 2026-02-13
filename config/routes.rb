Rails.application.routes.draw do
  devise_for :users
  
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Root - Mission Control Dashboard
  root "dashboard#index"
  
  # Dashboard
  get "dashboard", to: "dashboard#index"
  
  # Agents
  resources :agents
  
  # Agent Templates
  resources :agent_templates, only: [:index, :show] do
    member do
      post :deploy
    end
  end
  
  # Budgets
  resources :budgets, only: [:index] do
    collection do
      get :edit, to: "budgets#edit"
      patch :update, to: "budgets#update", as: ""
    end
  end
  
  # Analytics
  resources :analytics, only: [:index, :show]
  
  # Platform
  get "platform/status", to: "platform#status", as: :platform_status
  post "platform/restart", to: "platform#restart", as: :platform_restart
  post "platform/clear_cache", to: "platform#clear_cache", as: :platform_clear_cache
  
  # Webhooks
  post "webhooks/:channel_type", to: "webhooks#receive"
  
  # API v1
  namespace :api do
    namespace :v1 do
      resources :agents, only: [:index, :show, :create, :update, :destroy]
      resources :sessions, only: [:index, :show, :destroy]
    end
  end
  
  # Sidekiq Web UI (admin only)
  require "sidekiq/web"
  authenticate :user, ->(user) { user.admin? } do
    mount Sidekiq::Web => "/sidekiq"
  end
  
  # ActionCable
  mount ActionCable.server => "/cable"
end
