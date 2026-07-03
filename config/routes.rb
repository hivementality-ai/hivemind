Rails.application.routes.draw do
  devise_for :users

  # PWA manifest & service worker
  get "manifest", to: "pwa#manifest", as: :pwa_manifest
  get "service-worker", to: "pwa#service_worker", as: :pwa_service_worker

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
  get  "setup/openai_compatible_models", to: "setup#openai_compatible_models", as: :setup_openai_compatible_models

  # Mobile PWA Interface
  scope "/m", module: "mobile", as: "mobile" do
    root "home#index"                                    # Activity feed / quick actions
    resources :sessions, only: [ :index, :show, :create ] do
      member do
        post :message
        post :interrupt
      end
    end
    resources :team_chats, only: [ :index, :show ] do
      member do
        post :message
        post :interrupt
      end
    end
    resources :tasks, only: [ :index, :show ]            # Read-only task board
    get "agents",       to: "agents#index"               # Read-only agent list + status
    get "agents/:slug", to: "agents#show", as: :agent    # Read-only agent detail
    get "activity",     to: "activity#index"              # Recent activity feed
    get "settings",     to: "settings#index"              # Notification prefs, theme, desktop link
    post "settings/push_subscription", to: "settings#push_subscription"
    patch "settings/preferences", to: "settings#update_preferences"
  end

  # Root - Mission Control Dashboard
  root "dashboard#index"

  # Dashboard
  get "dashboard", to: "dashboard#index"

  # Chat Sessions
  resources :sessions, only: [ :index, :show, :create, :update ] do
    member do
      post :message
      post :interrupt
      get :canvas
      get :export
    end
  end

  # Team Chats
  get "team_chats", to: "team_chats#index", as: :team_chats_index
  resources :teams do
    resources :team_chats, only: [ :create ], path: "chats"
    resources :task_hooks, only: [ :index, :create, :edit, :update, :destroy ] do
      member do
        patch :toggle
      end
    end
    collection do
      controller :swarm_imports do
        get  :import_swarm
        post :upload_swarm
        get  :preview_swarm
        post :confirm_swarm
      end
    end
    member do
      get  :export
      post :export
    end
  end
  resources :team_chats, only: [ :show, :update ] do
    member do
      post :message
      post :interrupt
      get :export
    end
  end

  # Projects
  resources :projects do
    resources :milestones, controller: "project_milestones" do
      member do
        post :approve
        post :reject
        post :skip
      end
    end
    member do
      post :pause
      post :resume
      post :cancel
      post :archive
      post :upload_files
      delete :delete_file
    end
  end

  # Agents (use slug for routes)
  resources :agents, param: :slug do
    member do
      get :files
      post :upload_files
      delete :delete_file
      post :create_directory
      get :download_file
    end
  end

  # Workspace File Browser
  resources :workspace_files, only: [ :index ], path: "files" do
    collection do
      post :upload
      delete :delete
      post :create_directory
      get :download
    end
  end

  # Knowledge Base
  resources :knowledge_documents, path: "knowledge", only: [:index, :show, :new, :create, :destroy]

  # Providers (admin interface)
  resources :providers, only: [ :index, :show, :new, :create, :edit, :update ]

  # Tools
  resources :tools
  resources :skills do
    member do
      patch :toggle
      get :export
      patch :approve_proposal
      patch :reject_proposal
      get :history
      patch :rollback
    end
    collection do
      post :import
      get :review_import
      post :confirm_import
      get :export_bundle
      post :import_bundle
      get :proposals
      get :update_proposals
    end
  end

  resources :skill_update_proposals, only: [] do
    member do
      patch :approve_update_proposal, controller: :skills, action: :approve_update_proposal
      patch :reject_update_proposal, controller: :skills, action: :reject_update_proposal
    end
  end

  # Agent Templates
  resources :agent_templates, only: [ :index, :show ] do
    member do
      post :deploy
    end
  end

  # Tasks (kanban board)
  resources :tasks do
    member do
      patch :move
      patch :toggle_checklist
      patch :archive
    end
    resources :task_attachments, only: [ :create, :destroy ], shallow: true
    resources :task_hooks, only: [ :create, :destroy ], module: :tasks
  end



  # Hooks (top-level overview of all teams' hooks)
  get "hooks", to: "task_hooks#overview", as: :hooks_overview

  # Task Templates
  resources :task_templates

  # Budgets
  get "budgets", to: "budgets#index", as: :budgets
  patch "budgets/:agent_id", to: "budgets#update", as: :update_budget

  # Heartbeat
  get "heartbeat", to: "heartbeats#index", as: :heartbeats
  patch "heartbeat", to: "heartbeats#update", as: :update_heartbeat
  post "heartbeat/trigger", to: "heartbeats#trigger", as: :trigger_heartbeat
  patch "heartbeat/soul", to: "heartbeats#update_soul", as: :update_soul_heartbeat
  post "heartbeat/tasks/standing", to: "heartbeats#add_standing_task", as: :add_standing_heartbeat_task
  delete "heartbeat/tasks/standing", to: "heartbeats#delete_standing_task", as: :delete_standing_heartbeat_task
  delete "heartbeat/memories", to: "heartbeats#clear_memories", as: :clear_heartbeat_memories

  # Scheduled Tasks
  resources :scheduled_tasks, only: [ :index, :edit, :update, :destroy ] do
    member do
      patch :toggle
      post :run_now
    end
  end

  # Audit Log
  get "audit_logs", to: "audit_logs#index", as: :audit_logs

  # Analytics
  resources :analytics, only: [ :index, :show ] do
    member do
      get "payload/:usage_id", action: :payload, as: :payload
    end
  end

  # Plugins
  resources :plugins, only: [ :index, :show ] do
    member do
      post :enable
      post :disable
    end
  end

  # Embedding Migration
  get  "embedding_migration",          to: "embedding_migrations#show",     as: :embedding_migration
  post "embedding_migration/start",    to: "embedding_migrations#start",    as: :start_embedding_migration
  post "embedding_migration/validate", to: "embedding_migrations#validate", as: :validate_embedding_migration
  post "embedding_migration/cutover",  to: "embedding_migrations#cutover",  as: :cutover_embedding_migration
  post "embedding_migration/rollback", to: "embedding_migrations#rollback", as: :rollback_embedding_migration
  get  "embedding_migration/progress", to: "embedding_migrations#progress", as: :embedding_migration_progress

  # Platform
  get "platform/status", to: "platform#status", as: :platform_status
  get "platform/doctor", to: "platform#doctor", as: :platform_doctor
  post "platform/restart", to: "platform#restart", as: :platform_restart
  post "platform/clear_cache", to: "platform#clear_cache", as: :platform_clear_cache

  # Webhooks
  get "webhooks/:channel_type", to: "webhooks#verify"
  post "webhooks/:channel_type", to: "webhooks#receive"

  # Matrix Application Service: the homeserver PUTs event transactions here.
  # Point the AS registration `url` at this host; it appends the path below.
  put "_matrix/app/v1/transactions/:txn_id", to: "webhooks#receive", defaults: { channel_type: "matrix" }
  put "transactions/:txn_id", to: "webhooks#receive", defaults: { channel_type: "matrix" } # legacy r0 prefix

  # Integrations
  get "integrations", to: "integrations#index", as: :integrations
  patch "integrations/github", to: "integrations#update_github", as: :update_github_integrations
  get "integrations/github/test", to: "integrations#test_github", as: :test_github_integrations
  patch "integrations/gmail", to: "integrations#update_gmail", as: :update_gmail_integrations
  patch "integrations/email", to: "integrations#update_email", as: :update_email_integrations
  patch "integrations/jira", to: "integrations#update_jira", as: :update_jira_integrations
  get "integrations/jira/test", to: "integrations#test_jira", as: :test_jira_integrations
  patch "integrations/trello", to: "integrations#update_trello", as: :update_trello_integrations
  get "integrations/trello/test", to: "integrations#test_trello", as: :test_trello_integrations
  post "integrations/cloud_remote", to: "integrations#add_cloud_remote", as: :add_cloud_remote_integrations
  delete "integrations/cloud_remote", to: "integrations#remove_cloud_remote", as: :remove_cloud_remote_integrations
  get "integrations/cloud_remote/test", to: "integrations#test_cloud_remote", as: :test_cloud_remote_integrations
  patch "integrations/search", to: "integrations#update_search", as: :update_search_integrations
  get "integrations/search/test", to: "integrations#test_search", as: :test_search_integrations
  patch "integrations/google_workspace", to: "integrations#update_google_workspace", as: :update_google_workspace_integrations
  patch "integrations/embedding_key", to: "integrations#update_embedding_key", as: :update_embedding_key_integrations

  # Google Workspace OAuth
  get "oauth/google/authorize", to: "oauth/google#authorize", as: :oauth_google_authorize
  get "oauth/google/callback", to: "oauth/google#callback", as: :oauth_google_callback
  delete "oauth/google/disconnect", to: "oauth/google#disconnect", as: :oauth_google_disconnect

  # MCP Server Management
  post "integrations/mcp_servers", to: "integrations#create_mcp_server", as: :create_mcp_server
  patch "integrations/mcp_servers/:id", to: "integrations#update_mcp_server", as: :update_mcp_server
  delete "integrations/mcp_servers/:id", to: "integrations#destroy_mcp_server", as: :destroy_mcp_server
  post "integrations/mcp_servers/:id/connect", to: "integrations#connect_mcp_server", as: :connect_mcp_server
  post "integrations/mcp_servers/:id/disconnect", to: "integrations#disconnect_mcp_server", as: :disconnect_mcp_server
  get "integrations/mcp_servers/:id/refresh", to: "integrations#refresh_mcp_tools", as: :refresh_mcp_tools
  patch "integrations/mcp_servers/:id/toggle", to: "integrations#toggle_mcp_server", as: :toggle_mcp_server

  # API Integrations
  resources :api_integrations do
    member do
      post :test
    end
    collection do
      post :import
    end
  end

  # Migration Wizard
  get  "migration",            to: "migration#upload",     as: :migration
  post "migration/scan",       to: "migration#scan",       as: :migration_scan
  get  "migration/results",    to: "migration#results",    as: :migration_results
  get  "migration/review",     to: "migration#review",     as: :migration_review
  post "migration/import",     to: "migration#run_import", as: :migration_import
  get  "migration/reconnect",  to: "migration#reconnect",  as: :migration_reconnect

  resources :channels, except: [ :show ] do
    member do
      get :connect
      get :connector_health
      get :connector_qr
      post :connector_logout
    end
    resources :agent_channels, only: [ :create, :update, :destroy ]
  end

  # Internal API (SDK proxy callback — no Devise, CSRF)
  namespace :internal do
    post "tools/execute", to: "tools#execute"
  end

  # API v1
  namespace :api do
    namespace :v1 do
      resources :agents, only: [ :index, :show, :create, :update, :destroy ], param: :slug
      resources :sessions, only: [ :index, :show, :destroy ] do
        member do
          get :export
        end
      end
      post "plans/save", to: "plans#save", as: :save_plan
      get "providers/models", to: "providers#models"
      get "hashtag_actions", to: "hashtag_actions#index"
      get "system/version", to: "system#version"
      resources :projects, only: [ :index, :show, :create, :update ] do
        resources :milestones, only: [ :index, :show, :update ], controller: "project_milestones" do
          member do
            patch :approve
            patch :reject
          end
        end
      end
    end
  end

  # Sidekiq Web UI (admin only, with Cron tab)
  require "sidekiq/web"
  require "sidekiq/cron/web"
  Sidekiq::Web.use Rack::Auth::Basic, "Sidekiq" do |username, password|
    user = User.find_by(email: username)
    user&.valid_password?(password) && (user.admin? || user.owner?)
  end
  mount Sidekiq::Web => "/sidekiq"

  # ActionCable
  mount ActionCable.server => "/cable"
end
