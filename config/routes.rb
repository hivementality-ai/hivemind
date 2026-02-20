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
  get  "setup/ollama_models", to: "setup#ollama_models", as: :setup_ollama_models

  # Root - Mission Control Dashboard
  root "dashboard#index"

  # Dashboard
  get "dashboard", to: "dashboard#index"

  # Chat Sessions
  resources :sessions, only: [ :index, :show, :create ] do
    member do
      post :message
    end
  end

  # Team Chats
  get "team_chats", to: "team_chats#index", as: :team_chats_index
  resources :teams, only: [] do
    resources :team_chats, only: [ :create ], path: "chats"
  end
  resources :team_chats, only: [ :show ] do
    member do
      post :message
    end
  end

  # Agents (use slug for routes)
  resources :agents, param: :slug

  # Providers (admin interface)
  resources :providers, only: [ :index, :show, :edit, :update ]

  # Tools
  resources :tools
  resources :skills do
    member do
      patch :toggle
      get :export
    end
    collection do
      post :import
    end
  end

  # Agent Templates
  resources :agent_templates, only: [ :index, :show ] do
    member do
      post :deploy
    end
  end

  # Budgets
  get "budgets", to: "budgets#index", as: :budgets
  patch "budgets/:agent_id", to: "budgets#update", as: :update_budget

  # Heartbeat
  get "heartbeat", to: "heartbeats#index", as: :heartbeats
  patch "heartbeat", to: "heartbeats#update", as: :update_heartbeat
  post "heartbeat/trigger", to: "heartbeats#trigger", as: :trigger_heartbeat

  # Analytics
  resources :analytics, only: [ :index, :show ]

  # Platform
  get "platform/status", to: "platform#status", as: :platform_status
  post "platform/restart", to: "platform#restart", as: :platform_restart
  post "platform/clear_cache", to: "platform#clear_cache", as: :platform_clear_cache

  # Webhooks
  get "webhooks/:channel_type", to: "webhooks#verify"
  post "webhooks/:channel_type", to: "webhooks#receive"

  # Integrations
  get "integrations", to: "integrations#index", as: :integrations
  patch "integrations/github", to: "integrations#update_github", as: :update_github_integrations
  get "integrations/github/test", to: "integrations#test_github", as: :test_github_integrations
  patch "integrations/gmail", to: "integrations#update_gmail", as: :update_gmail_integrations
  patch "integrations/email", to: "integrations#update_email", as: :update_email_integrations
  patch "integrations/jira", to: "integrations#update_jira", as: :update_jira_integrations
  get "integrations/jira/test", to: "integrations#test_jira", as: :test_jira_integrations
  post "integrations/cloud_remote", to: "integrations#add_cloud_remote", as: :add_cloud_remote_integrations
  delete "integrations/cloud_remote", to: "integrations#remove_cloud_remote", as: :remove_cloud_remote_integrations
  get "integrations/cloud_remote/test", to: "integrations#test_cloud_remote", as: :test_cloud_remote_integrations
  patch "integrations/search", to: "integrations#update_search", as: :update_search_integrations
  get "integrations/search/test", to: "integrations#test_search", as: :test_search_integrations

  # API Integrations
  resources :api_integrations do
    member do
      post :test
    end
    collection do
      post :import
    end
  end

  resources :channels, except: [ :show ] do
    member do
      get :connect
    end
    resources :agent_channels, only: [ :create, :update, :destroy ]
  end

  # API v1
  namespace :api do
    namespace :v1 do
      resources :agents, only: [ :index, :show, :create, :update, :destroy ], param: :slug
      resources :sessions, only: [ :index, :show, :destroy ]
      get "providers/models", to: "providers#models"
      get "hashtag_actions", to: "hashtag_actions#index"
      get "system/version", to: "system#version"
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
