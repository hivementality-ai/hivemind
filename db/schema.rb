# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_13_190002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_budgets", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.decimal "limit_cents"
    t.string "period"
    t.datetime "reset_at"
    t.decimal "spent_cents"
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_agent_budgets_on_agent_id"
  end

  create_table "agent_templates", force: :cascade do |t|
    t.string "author"
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "featured", default: false
    t.string "icon"
    t.jsonb "model_config", default: {}, null: false
    t.string "name", null: false
    t.string "role", null: false
    t.text "soul_md"
    t.text "system_prompt"
    t.jsonb "tools_config", default: {}, null: false
    t.datetime "updated_at", null: false
    t.string "version", default: "1.0.0"
    t.index ["category"], name: "index_agent_templates_on_category"
    t.index ["featured"], name: "index_agent_templates_on_featured"
  end

  create_table "agents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "current_task"
    t.decimal "daily_budget_limit", precision: 10, scale: 4, default: "10.0"
    t.boolean "enabled", default: true, null: false
    t.string "llm_model", default: "gpt-4"
    t.jsonb "model_config"
    t.string "model_provider", default: "openai"
    t.decimal "monthly_budget_limit", precision: 10, scale: 4, default: "100.0"
    t.string "name"
    t.string "role"
    t.integer "status"
    t.text "system_prompt"
    t.bigint "team_id"
    t.jsonb "tools_config"
    t.datetime "updated_at", null: false
    t.string "workspace_path"
    t.index ["enabled"], name: "index_agents_on_enabled"
    t.index ["name"], name: "index_agents_on_name", unique: true
    t.index ["status"], name: "index_agents_on_status"
    t.index ["team_id"], name: "index_agents_on_team_id"
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "name"
    t.datetime "revoked_at"
    t.jsonb "scopes"
    t.string "token_digest"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "approval_requests", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.jsonb "params", default: {}, null: false
    t.datetime "requested_at", null: false
    t.text "resolution_notes"
    t.datetime "resolved_at"
    t.string "resolved_by"
    t.string "resource", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "status"], name: "index_approval_requests_on_agent_id_and_status"
    t.index ["agent_id"], name: "index_approval_requests_on_agent_id"
    t.index ["expires_at"], name: "index_approval_requests_on_expires_at"
    t.index ["status"], name: "index_approval_requests_on_status"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action"
    t.string "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.jsonb "metadata"
    t.string "resource"
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_type", "actor_id"], name: "index_audit_logs_on_actor_type_and_actor_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
  end

  create_table "channels", force: :cascade do |t|
    t.string "channel_type"
    t.jsonb "config"
    t.datetime "created_at", null: false
    t.boolean "enabled"
    t.string "name"
    t.datetime "updated_at", null: false
    t.string "webhook_path"
    t.index ["channel_type"], name: "index_channels_on_channel_type"
  end

  create_table "device_pairings", force: :cascade do |t|
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.string "device_id"
    t.string "device_name"
    t.string "device_type"
    t.jsonb "metadata"
    t.string "name"
    t.integer "status"
    t.string "token_digest"
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_device_pairings_on_device_id", unique: true
    t.index ["status"], name: "index_device_pairings_on_status"
  end

  create_table "inbound_messages", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "received_at", null: false
    t.string "sender", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "external_id"], name: "index_inbound_messages_on_channel_id_and_external_id", unique: true
    t.index ["channel_id"], name: "index_inbound_messages_on_channel_id"
    t.index ["received_at"], name: "index_inbound_messages_on_received_at"
  end

  create_table "memory_entries", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.jsonb "embedding", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_memory_entries_on_agent_id"
    t.index ["source_type", "source_id"], name: "index_memory_entries_on_source_type_and_source_id"
  end

  create_table "outbound_messages", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "recipient", null: false
    t.datetime "sent_at", null: false
    t.string "status", default: "sent"
    t.datetime "updated_at", null: false
    t.index ["channel_id"], name: "index_outbound_messages_on_channel_id"
    t.index ["sent_at"], name: "index_outbound_messages_on_sent_at"
  end

  create_table "provider_configs", force: :cascade do |t|
    t.string "adapter_type", null: false
    t.string "base_url"
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true
    t.jsonb "model_definitions", default: []
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "vault_key"
    t.index ["name"], name: "index_provider_configs_on_name", unique: true
  end

  create_table "scheduled_tasks", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled"
    t.string "job_class"
    t.string "last_error_at"
    t.datetime "last_run_at"
    t.string "name"
    t.datetime "next_run_at"
    t.jsonb "params"
    t.string "schedule"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "enabled"], name: "index_scheduled_tasks_on_agent_id_and_enabled"
    t.index ["agent_id"], name: "index_scheduled_tasks_on_agent_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.bigint "input_tokens"
    t.datetime "last_activity_at"
    t.jsonb "metadata"
    t.bigint "output_tokens"
    t.string "session_key"
    t.integer "status"
    t.string "title"
    t.bigint "total_tokens"
    t.jsonb "transcript"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "status"], name: "index_sessions_on_agent_id_and_status"
    t.index ["agent_id"], name: "index_sessions_on_agent_id"
    t.index ["last_activity_at"], name: "index_sessions_on_last_activity_at"
    t.index ["session_key"], name: "index_sessions_on_session_key", unique: true
  end

  create_table "team_messages", force: :cascade do |t|
    t.datetime "completed_at"
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "from_agent_id", null: false
    t.string "message_type"
    t.jsonb "metadata"
    t.string "status", default: "pending"
    t.bigint "team_id", null: false
    t.bigint "to_agent_id"
    t.datetime "updated_at", null: false
    t.index ["from_agent_id"], name: "index_team_messages_on_from_agent_id"
    t.index ["status"], name: "index_team_messages_on_status"
    t.index ["team_id", "created_at"], name: "index_team_messages_on_team_id_and_created_at"
    t.index ["team_id"], name: "index_team_messages_on_team_id"
    t.index ["to_agent_id"], name: "index_team_messages_on_to_agent_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_teams_on_name", unique: true
  end

  create_table "transcript_archives", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.bigint "session_id", null: false
    t.jsonb "transcript"
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_transcript_archives_on_session_id"
  end

  create_table "usage_records", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.integer "cache_tokens", default: 0
    t.decimal "cost_cents", precision: 10, scale: 4, default: "0.0"
    t.datetime "created_at", null: false
    t.integer "input_tokens", default: 0
    t.string "llm_model"
    t.jsonb "metadata", default: {}
    t.integer "output_tokens", default: 0
    t.string "provider", null: false
    t.bigint "session_id"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "created_at"], name: "index_usage_records_on_agent_id_and_created_at"
    t.index ["agent_id"], name: "index_usage_records_on_agent_id"
    t.index ["created_at"], name: "index_usage_records_on_created_at"
    t.index ["session_id"], name: "index_usage_records_on_session_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "vault_entries", force: :cascade do |t|
    t.bigint "agent_id"
    t.datetime "created_at", null: false
    t.text "encrypted_value"
    t.string "key"
    t.jsonb "metadata"
    t.string "namespace"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "namespace", "key"], name: "idx_vault_unique_entry", unique: true
    t.index ["agent_id"], name: "index_vault_entries_on_agent_id"
  end

  add_foreign_key "agent_budgets", "agents"
  add_foreign_key "agents", "teams"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "approval_requests", "agents"
  add_foreign_key "inbound_messages", "channels"
  add_foreign_key "memory_entries", "agents"
  add_foreign_key "outbound_messages", "channels"
  add_foreign_key "scheduled_tasks", "agents"
  add_foreign_key "sessions", "agents"
  add_foreign_key "team_messages", "agents", column: "from_agent_id"
  add_foreign_key "team_messages", "agents", column: "to_agent_id"
  add_foreign_key "team_messages", "teams"
  add_foreign_key "transcript_archives", "sessions"
  add_foreign_key "usage_records", "agents"
  add_foreign_key "usage_records", "sessions"
  add_foreign_key "vault_entries", "agents"
end
