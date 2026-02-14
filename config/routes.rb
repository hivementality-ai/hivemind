Rails.application.routes.draw do
  devise_for :users
  
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Setup Wizard (first-run onboarding)
  get  "setup",          to: "setup#index",          as: :setup
  get  "setup/account",  to: "setup#account",        as: :setup_account
  post "setup/account",  to: "setup#create_account"
  get  "setup/provider", to: "setup#provider",       as: :setup_provider
  post "setup/provider", to: "setup#save_provider"
  get  "setup/team",     to: "setup#team",           as: :setup_team
  post "setup/team",     to: "setup#save_team"
  get  "setup/agent",    to: "setup#agent",          as: :setup_agent
  post "setup/agent",    to: "setup#save_agent"
  get  "setup/complete", to: "setup#complete",        as: :setup_complete

  # Root - Mission Control Dashboard
  root "dashboard#index"
  
  # Dashboard
  get "dashboard", to: "dashboard#index"
  
  # Chat Sessions
  resources :sessions, only: [:index, :show, :create] do
    member do
      post :message
    end
  end

  # Team Chats
  get "team_chats", to: "team_chats#index", as: :team_chats_index
  resources :teams, only: [] do
    resources :team_chats, only: [:create], path: "chats"
  end
  resources :team_chats, only: [:show] do
    member do
      post :message
    end
  end

  # Agents
  resources :agents

  # Tools
  resources :tools
  
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
      get "providers/models", to: "providers#models"
    end
  end
  
  # Sidekiq Web UI (admin only)
  require "sidekiq/web"
  authenticate :user, ->(user) { user.admin? || user.owner? } do
    mount Sidekiq::Web => "/sidekiq"
  end
  
  # ActionCable
  mount ActionCable.server => "/cable"
end
