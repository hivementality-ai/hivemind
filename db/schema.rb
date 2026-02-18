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

ActiveRecord::Schema[8.1].define(version: 2026_02_18_105215) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

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

  create_table "agent_channels", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.bigint "channel_id", null: false
    t.jsonb "config", default: {}
    t.datetime "created_at", null: false
    t.string "external_bot_user_id"
    t.boolean "is_default", default: false
    t.datetime "updated_at", null: false
    t.string "vault_token_key"
    t.index ["agent_id", "channel_id"], name: "index_agent_channels_on_agent_id_and_channel_id", unique: true
    t.index ["agent_id"], name: "index_agent_channels_on_agent_id"
    t.index ["channel_id"], name: "index_agent_channels_on_channel_id"
  end

  create_table "agent_skills", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.bigint "skill_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "skill_id"], name: "index_agent_skills_on_agent_id_and_skill_id", unique: true
    t.index ["agent_id"], name: "index_agent_skills_on_agent_id"
    t.index ["skill_id"], name: "index_agent_skills_on_skill_id"
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

  create_table "agent_tools", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "tool_id"], name: "index_agent_tools_on_agent_id_and_tool_id", unique: true
    t.index ["agent_id"], name: "index_agent_tools_on_agent_id"
    t.index ["tool_id"], name: "index_agent_tools_on_tool_id"
  end

  create_table "agents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "current_task"
    t.text "custom_instructions"
    t.decimal "daily_budget_limit", precision: 10, scale: 4, default: "10.0"
    t.boolean "enabled", default: true, null: false
    t.boolean "heartbeat_enabled", default: false, null: false
    t.integer "heartbeat_interval_minutes", default: 30, null: false
    t.datetime "heartbeat_last_run_at"
    t.text "heartbeat_prompt"
    t.string "llm_model", default: "gpt-5.2"
    t.jsonb "model_config"
    t.string "model_provider", default: "openai"
    t.decimal "monthly_budget_limit", precision: 10, scale: 4, default: "100.0"
    t.string "name"
    t.string "role"
    t.citext "slug", null: false
    t.integer "status"
    t.boolean "system_agent", default: false, null: false
    t.text "system_prompt"
    t.bigint "team_id"
    t.integer "thinking_budget_tokens", default: 10000
    t.boolean "thinking_enabled", default: false, null: false
    t.string "thinking_visibility", default: "hidden"
    t.jsonb "tools_config"
    t.datetime "updated_at", null: false
    t.string "workspace_path"
    t.index ["enabled"], name: "index_agents_on_enabled"
    t.index ["name"], name: "index_agents_on_name", unique: true
    t.index ["slug"], name: "index_agents_on_slug", unique: true
    t.index ["status"], name: "index_agents_on_status"
    t.index ["team_id"], name: "index_agents_on_team_id"
  end

  create_table "api_integrations", force: :cascade do |t|
    t.jsonb "auth_config", default: {}
    t.string "base_url", null: false
    t.datetime "created_at", null: false
    t.jsonb "default_headers", default: {}
    t.text "description"
    t.boolean "enabled", default: true
    t.jsonb "endpoints", default: []
    t.integer "max_response_bytes", default: 1048576
    t.string "name", null: false
    t.jsonb "spec_data", default: {}
    t.string "spec_format", default: "openapi"
    t.integer "timeout_seconds", default: 30
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["enabled"], name: "index_api_integrations_on_enabled"
    t.index ["name"], name: "index_api_integrations_on_name", unique: true
    t.index ["user_id"], name: "index_api_integrations_on_user_id"
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

  create_table "channel_threads", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.string "external_thread_id", null: false
    t.datetime "last_active_at"
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_channel_threads_on_agent_id"
    t.index ["channel_id", "external_thread_id"], name: "index_channel_threads_on_channel_id_and_external_thread_id", unique: true
    t.index ["channel_id"], name: "index_channel_threads_on_channel_id"
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

  create_table "chat_attachments", force: :cascade do |t|
    t.integer "byte_size"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename"
    t.integer "message_index"
    t.bigint "session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_chat_attachments_on_session_id"
  end

  create_table "coding_agent_tasks", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.string "cli"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "model"
    t.text "output"
    t.json "process_info"
    t.bigint "session_id", null: false
    t.datetime "started_at"
    t.string "status"
    t.text "task"
    t.string "task_key"
    t.integer "timeout"
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_coding_agent_tasks_on_agent_id"
    t.index ["session_id"], name: "index_coding_agent_tasks_on_session_id"
    t.index ["task_key"], name: "index_coding_agent_tasks_on_task_key", unique: true
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
    t.vector "embedding", limit: 1536
    t.jsonb "metadata", default: {}, null: false
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_memory_entries_on_agent_id"
    t.index ["embedding"], name: "index_memory_entries_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
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
    t.string "confirmation_status", default: "active"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled"
    t.string "job_class"
    t.jsonb "job_params"
    t.datetime "last_error_at"
    t.datetime "last_run_at"
    t.string "name"
    t.datetime "next_run_at"
    t.jsonb "params"
    t.string "schedule"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "confirmation_status"], name: "index_scheduled_tasks_on_agent_id_and_confirmation_status"
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
    t.bigint "team_chat_session_id"
    t.string "title"
    t.bigint "total_tokens"
    t.jsonb "transcript"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "status"], name: "index_sessions_on_agent_id_and_status"
    t.index ["agent_id"], name: "index_sessions_on_agent_id"
    t.index ["last_activity_at"], name: "index_sessions_on_last_activity_at"
    t.index ["session_key"], name: "index_sessions_on_session_key", unique: true
    t.index ["team_chat_session_id"], name: "index_sessions_on_team_chat_session_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "skill_tools", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "skill_id", null: false
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["skill_id", "tool_id"], name: "index_skill_tools_on_skill_id_and_tool_id", unique: true
    t.index ["skill_id"], name: "index_skill_tools_on_skill_id"
    t.index ["tool_id"], name: "index_skill_tools_on_tool_id"
  end

  create_table "skills", force: :cascade do |t|
    t.boolean "builtin", default: false, null: false
    t.string "category"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_skills_on_enabled"
    t.index ["name"], name: "index_skills_on_name", unique: true
  end

  create_table "sub_agent_tasks", force: :cascade do |t|
    t.bigint "child_agent_id", null: false
    t.bigint "child_session_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "parent_agent_id", null: false
    t.bigint "parent_session_id"
    t.text "result"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.text "task", null: false
    t.string "task_key", null: false
    t.datetime "updated_at", null: false
    t.index ["child_agent_id"], name: "index_sub_agent_tasks_on_child_agent_id"
    t.index ["child_session_id"], name: "index_sub_agent_tasks_on_child_session_id"
    t.index ["parent_agent_id"], name: "index_sub_agent_tasks_on_parent_agent_id"
    t.index ["parent_session_id"], name: "index_sub_agent_tasks_on_parent_session_id"
    t.index ["status"], name: "index_sub_agent_tasks_on_status"
    t.index ["task_key"], name: "index_sub_agent_tasks_on_task_key", unique: true
  end

  create_table "team_chat_messages", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}
    t.bigint "sender_id", null: false
    t.string "sender_type", null: false
    t.bigint "target_agent_id"
    t.bigint "team_chat_session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sender_type", "sender_id"], name: "index_team_chat_messages_on_sender_type_and_sender_id"
    t.index ["target_agent_id"], name: "index_team_chat_messages_on_target_agent_id"
    t.index ["team_chat_session_id"], name: "index_team_chat_messages_on_team_chat_session_id"
  end

  create_table "team_chat_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}
    t.string "session_key"
    t.integer "status", default: 0, null: false
    t.bigint "team_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["session_key"], name: "index_team_chat_sessions_on_session_key", unique: true
    t.index ["team_id"], name: "index_team_chat_sessions_on_team_id"
    t.index ["user_id"], name: "index_team_chat_sessions_on_user_id"
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
    t.text "custom_soul"
    t.text "description"
    t.string "name"
    t.text "soul"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_teams_on_name", unique: true
  end

  create_table "tool_executions", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error"
    t.integer "exit_code"
    t.jsonb "input", default: {}, null: false
    t.text "output"
    t.bigint "session_id", null: false
    t.string "status", default: "pending", null: false
    t.bigint "tool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_tool_executions_on_agent_id"
    t.index ["session_id"], name: "index_tool_executions_on_session_id"
    t.index ["status"], name: "index_tool_executions_on_status"
    t.index ["tool_id"], name: "index_tool_executions_on_tool_id"
  end

  create_table "tools", force: :cascade do |t|
    t.boolean "builtin", default: false, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.boolean "enabled", default: true, null: false
    t.string "executor_type", null: false
    t.string "name", null: false
    t.jsonb "parameters_schema", default: {}, null: false
    t.boolean "requires_approval", default: false, null: false
    t.text "script_template"
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_tools_on_enabled"
    t.index ["name"], name: "index_tools_on_name", unique: true
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_budgets", "agents"
  add_foreign_key "agent_channels", "agents"
  add_foreign_key "agent_channels", "channels"
  add_foreign_key "agent_skills", "agents"
  add_foreign_key "agent_skills", "skills"
  add_foreign_key "agent_tools", "agents"
  add_foreign_key "agent_tools", "tools"
  add_foreign_key "agents", "teams"
  add_foreign_key "api_integrations", "users"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "approval_requests", "agents"
  add_foreign_key "channel_threads", "agents"
  add_foreign_key "channel_threads", "channels"
  add_foreign_key "chat_attachments", "sessions"
  add_foreign_key "coding_agent_tasks", "agents"
  add_foreign_key "coding_agent_tasks", "sessions"
  add_foreign_key "inbound_messages", "channels"
  add_foreign_key "memory_entries", "agents"
  add_foreign_key "outbound_messages", "channels"
  add_foreign_key "scheduled_tasks", "agents"
  add_foreign_key "sessions", "agents"
  add_foreign_key "sessions", "team_chat_sessions"
  add_foreign_key "skill_tools", "skills"
  add_foreign_key "skill_tools", "tools"
  add_foreign_key "sub_agent_tasks", "agents", column: "child_agent_id"
  add_foreign_key "sub_agent_tasks", "agents", column: "parent_agent_id"
  add_foreign_key "sub_agent_tasks", "sessions", column: "child_session_id"
  add_foreign_key "sub_agent_tasks", "sessions", column: "parent_session_id"
  add_foreign_key "team_chat_messages", "team_chat_sessions"
  add_foreign_key "team_chat_sessions", "teams"
  add_foreign_key "team_chat_sessions", "users"
  add_foreign_key "team_messages", "agents", column: "from_agent_id"
  add_foreign_key "team_messages", "agents", column: "to_agent_id"
  add_foreign_key "team_messages", "teams"
  add_foreign_key "tool_executions", "agents"
  add_foreign_key "tool_executions", "sessions"
  add_foreign_key "tool_executions", "tools"
  add_foreign_key "transcript_archives", "sessions"
  add_foreign_key "usage_records", "agents"
  add_foreign_key "usage_records", "sessions"
  add_foreign_key "vault_entries", "agents"
end
