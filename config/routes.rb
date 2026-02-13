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
