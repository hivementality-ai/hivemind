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

ActiveRecord::Schema[8.1].define(version: 2026_07_02_000001) do
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
    t.jsonb "dm_policy", default: {}, null: false
    t.string "external_bot_user_id"
    t.boolean "is_default", default: false
    t.datetime "updated_at", null: false
    t.string "vault_token_key"
    t.index ["agent_id", "channel_id"], name: "index_agent_channels_on_agent_id_and_channel_id", unique: true
    t.index ["agent_id"], name: "index_agent_channels_on_agent_id"
    t.index ["channel_id"], name: "index_agent_channels_on_channel_id"
  end

  create_table "agent_mcp_servers", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.bigint "mcp_server_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "mcp_server_id"], name: "index_agent_mcp_servers_on_agent_id_and_mcp_server_id", unique: true
    t.index ["agent_id"], name: "index_agent_mcp_servers_on_agent_id"
    t.index ["mcp_server_id"], name: "index_agent_mcp_servers_on_mcp_server_id"
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
    t.jsonb "skills_config", default: {}, null: false
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
    t.jsonb "egress_policy", default: {}, null: false
    t.boolean "enabled", default: true, null: false
    t.boolean "heartbeat_enabled", default: false, null: false
    t.integer "heartbeat_interval_minutes", default: 30, null: false
    t.datetime "heartbeat_last_run_at"
    t.text "heartbeat_prompt"
    t.string "llm_model", default: "gpt-5.4"
    t.jsonb "model_config"
    t.string "model_provider", default: "openai"
    t.decimal "monthly_budget_limit", precision: 10, scale: 4, default: "100.0"
    t.string "name"
    t.bigint "reports_to_id"
    t.string "role"
    t.citext "slug", null: false
    t.integer "status"
    t.boolean "system_agent", default: false, null: false
    t.text "system_prompt"
    t.bigint "team_id"
    t.integer "thinking_budget_tokens", default: 10000
    t.boolean "thinking_enabled", default: false, null: false
    t.string "thinking_visibility", default: "hidden"
    t.string "title"
    t.jsonb "tool_loop_config", default: {}, null: false
    t.jsonb "tools_config"
    t.datetime "updated_at", null: false
    t.string "workspace_path"
    t.index ["enabled"], name: "index_agents_on_enabled"
    t.index ["name"], name: "index_agents_on_name", unique: true
    t.index ["reports_to_id"], name: "index_agents_on_reports_to_id"
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
    t.jsonb "routing_rules", default: [], null: false
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

  create_table "delivery_queue_entries", force: :cascade do |t|
    t.bigint "agent_id"
    t.integer "attempts", default: 0, null: false
    t.bigint "channel_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.text "last_error"
    t.integer "max_attempts", default: 5, null: false
    t.datetime "next_attempt_at"
    t.jsonb "options", default: {}
    t.string "recipient", null: false
    t.datetime "sent_at"
    t.bigint "session_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_delivery_queue_entries_on_agent_id"
    t.index ["channel_id"], name: "index_delivery_queue_entries_on_channel_id"
    t.index ["session_id"], name: "index_delivery_queue_entries_on_session_id"
    t.index ["status", "next_attempt_at"], name: "index_delivery_queue_entries_on_status_and_next_attempt_at"
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

  create_table "embedding_migration_statuses", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "from_provider", null: false
    t.string "phase", default: "shadow", null: false
    t.datetime "rolled_back_at"
    t.datetime "started_at"
    t.string "to_provider", null: false
    t.datetime "updated_at", null: false
    t.datetime "validated_at"
    t.jsonb "validation_results", default: {}
  end

  create_table "heartbeat_runs", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.integer "input_tokens", default: 0
    t.jsonb "metadata", default: {}
    t.string "model"
    t.integer "output_tokens", default: 0
    t.text "previous_summary"
    t.bigint "session_id"
    t.string "status", default: "ok", null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_heartbeat_runs_on_agent_id"
    t.index ["created_at"], name: "index_heartbeat_runs_on_created_at"
    t.index ["session_id"], name: "index_heartbeat_runs_on_session_id"
    t.index ["status"], name: "index_heartbeat_runs_on_status"
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

  create_table "knowledge_chunks", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 768
    t.bigint "knowledge_document_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "knowledge_document_id"], name: "index_knowledge_chunks_on_agent_id_and_knowledge_document_id"
    t.index ["agent_id"], name: "index_knowledge_chunks_on_agent_id"
    t.index ["embedding"], name: "index_knowledge_chunks_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["knowledge_document_id"], name: "index_knowledge_chunks_on_knowledge_document_id"
  end

  create_table "knowledge_documents", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.text "error"
    t.jsonb "metadata", default: {}, null: false
    t.string "source_type", default: "text", null: false
    t.string "source_url"
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "status"], name: "index_knowledge_documents_on_agent_id_and_status"
    t.index ["agent_id"], name: "index_knowledge_documents_on_agent_id"
  end

  create_table "mcp_servers", force: :cascade do |t|
    t.jsonb "auth_config", default: {}
    t.string "command"
    t.datetime "created_at", null: false
    t.jsonb "discovered_tools", default: []
    t.boolean "enabled", default: true
    t.jsonb "env_vars", default: {}
    t.string "icon"
    t.datetime "last_connected_at"
    t.text "last_error"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.string "npm_package"
    t.boolean "preset", default: false
    t.string "status", default: "disconnected"
    t.datetime "tools_refreshed_at"
    t.string "transport", default: "stdio", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["enabled"], name: "index_mcp_servers_on_enabled"
    t.index ["name"], name: "index_mcp_servers_on_name", unique: true
    t.index ["transport"], name: "index_mcp_servers_on_transport"
  end

  create_table "memory_entries", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.string "category", default: "general", null: false
    t.boolean "consolidated", default: false, null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 768
    t.string "embedding_model"
    t.string "embedding_provider"
    t.float "importance", default: 0.5, null: false
    t.datetime "last_accessed_at"
    t.string "memory_type", default: "episodic", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "modality", default: "text", null: false
    t.vector "shadow_embedding", limit: 768
    t.bigint "source_id"
    t.string "source_type"
    t.string "status", default: "active", null: false
    t.bigint "superseded_by_id"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "category", "status"], name: "index_memory_entries_on_agent_id_category_status"
    t.index ["agent_id", "memory_type"], name: "index_memory_entries_on_agent_id_and_memory_type"
    t.index ["agent_id"], name: "index_memory_entries_on_agent_id"
    t.index ["consolidated"], name: "index_memory_entries_on_consolidated"
    t.index ["embedding"], name: "index_memory_entries_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["importance"], name: "index_memory_entries_on_importance"
    t.index ["memory_type"], name: "index_memory_entries_on_memory_type"
    t.index ["shadow_embedding"], name: "index_memory_entries_on_shadow_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["source_type", "source_id"], name: "index_memory_entries_on_source_type_and_source_id"
  end

  create_table "outbound_messages", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "platform_message_id"
    t.string "recipient", null: false
    t.datetime "sent_at", null: false
    t.string "status", default: "sent"
    t.datetime "updated_at", null: false
    t.index ["channel_id"], name: "index_outbound_messages_on_channel_id"
    t.index ["platform_message_id"], name: "index_outbound_messages_on_platform_message_id"
    t.index ["sent_at"], name: "index_outbound_messages_on_sent_at"
  end

  create_table "project_events", force: :cascade do |t|
    t.bigint "agent_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "project_id", null: false
    t.bigint "project_milestone_id"
    t.text "summary", null: false
    t.bigint "user_id"
    t.index ["agent_id"], name: "index_project_events_on_agent_id"
    t.index ["event_type"], name: "index_project_events_on_event_type"
    t.index ["project_id", "created_at"], name: "index_project_events_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_project_events_on_project_id"
    t.index ["project_milestone_id"], name: "index_project_events_on_project_milestone_id"
    t.index ["user_id"], name: "index_project_events_on_user_id"
  end

  create_table "project_milestones", force: :cascade do |t|
    t.text "acceptance_criteria"
    t.bigint "agent_id"
    t.text "agent_notes"
    t.jsonb "checkpoint", default: {}, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "deliverables", default: [], null: false
    t.jsonb "depends_on", default: [], null: false
    t.text "description"
    t.datetime "last_ping_at"
    t.integer "max_retries", default: 3, null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "ping_count", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.bigint "project_id", null: false
    t.boolean "requires_approval", default: true, null: false
    t.integer "retry_count", default: 0, null: false
    t.text "review_notes"
    t.datetime "reviewed_at"
    t.bigint "session_id"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_project_milestones_on_agent_id"
    t.index ["project_id", "position"], name: "index_project_milestones_on_project_id_and_position"
    t.index ["project_id", "status"], name: "index_project_milestones_on_project_id_and_status"
    t.index ["project_id"], name: "index_project_milestones_on_project_id"
    t.index ["session_id"], name: "index_project_milestones_on_session_id"
    t.index ["status"], name: "index_project_milestones_on_status"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "deadline"
    t.text "description"
    t.bigint "lead_agent_id"
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "notification_prefs", default: {}, null: false
    t.string "priority", default: "normal", null: false
    t.datetime "started_at"
    t.string "status", default: "planning", null: false
    t.bigint "team_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["lead_agent_id"], name: "index_projects_on_lead_agent_id"
    t.index ["status"], name: "index_projects_on_status"
    t.index ["team_id", "status"], name: "index_projects_on_team_id_and_status"
    t.index ["team_id"], name: "index_projects_on_team_id"
    t.index ["user_id"], name: "index_projects_on_user_id"
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

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.string "p256dh", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "endpoint"], name: "index_push_subscriptions_on_user_id_and_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "research_sessions", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "current_phase"
    t.string "depth", default: "standard", null: false
    t.text "error_message"
    t.jsonb "findings", default: []
    t.string "focus", default: "general", null: false
    t.string "output_format", default: "report", null: false
    t.jsonb "progress_log", default: []
    t.string "query", null: false
    t.text "report"
    t.bigint "session_id", null: false
    t.jsonb "sources", default: []
    t.integer "sources_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.string "task_key", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "created_at"], name: "index_research_sessions_on_agent_id_and_created_at"
    t.index ["agent_id"], name: "index_research_sessions_on_agent_id"
    t.index ["session_id"], name: "index_research_sessions_on_session_id"
    t.index ["status"], name: "index_research_sessions_on_status"
    t.index ["task_key"], name: "index_research_sessions_on_task_key", unique: true
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
    t.text "conversation_summary"
    t.datetime "created_at", null: false
    t.tsvector "fts_vector"
    t.bigint "input_tokens"
    t.datetime "last_activity_at"
    t.jsonb "metadata"
    t.bigint "origin_channel_id"
    t.string "origin_channel_type"
    t.string "origin_sender"
    t.bigint "output_tokens"
    t.string "session_key"
    t.integer "status"
    t.integer "summary_through_index", default: 0
    t.bigint "team_chat_session_id"
    t.string "title"
    t.bigint "total_tokens"
    t.jsonb "transcript"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "status"], name: "index_sessions_on_agent_id_and_status"
    t.index ["agent_id"], name: "index_sessions_on_agent_id"
    t.index ["fts_vector"], name: "index_sessions_on_fts_vector", using: :gin
    t.index ["last_activity_at"], name: "index_sessions_on_last_activity_at"
    t.index ["origin_channel_type", "origin_sender"], name: "index_sessions_on_origin_channel_type_and_origin_sender"
    t.index ["origin_channel_type"], name: "index_sessions_on_origin_channel_type"
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

  create_table "skill_load_events", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.datetime "flagged_at"
    t.text "flagged_reason"
    t.string "load_tier", null: false
    t.float "relevance_score"
    t.bigint "session_id"
    t.bigint "skill_id", null: false
    t.string "trigger_context", limit: 500
    t.boolean "was_helpful"
    t.index ["agent_id", "skill_id"], name: "index_skill_load_events_on_agent_and_skill"
    t.index ["agent_id"], name: "index_skill_load_events_on_agent_id"
    t.index ["created_at"], name: "index_skill_load_events_on_created_at"
    t.index ["load_tier"], name: "index_skill_load_events_on_load_tier"
    t.index ["session_id"], name: "index_skill_load_events_on_session_id"
    t.index ["skill_id"], name: "index_skill_load_events_on_skill_id"
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

  create_table "skill_update_proposals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "original_content", null: false
    t.bigint "proposed_by_agent_id", null: false
    t.text "proposed_content", null: false
    t.text "rationale", null: false
    t.text "review_notes"
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_user_id"
    t.bigint "skill_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["proposed_by_agent_id"], name: "index_skill_update_proposals_on_proposed_by_agent_id"
    t.index ["skill_id", "status"], name: "index_skill_update_proposals_on_skill_id_and_status"
    t.index ["skill_id"], name: "index_skill_update_proposals_on_skill_id"
    t.index ["status"], name: "index_skill_update_proposals_on_status"
  end

  create_table "skill_versions", force: :cascade do |t|
    t.string "change_source", default: "manual", null: false
    t.text "change_summary"
    t.bigint "changed_by_agent_id"
    t.bigint "changed_by_user_id"
    t.string "checksum", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.bigint "skill_id", null: false
    t.bigint "update_proposal_id"
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["change_source"], name: "index_skill_versions_on_change_source"
    t.index ["checksum"], name: "index_skill_versions_on_checksum"
    t.index ["skill_id", "version_number"], name: "index_skill_versions_on_skill_id_and_version_number", unique: true
    t.index ["skill_id"], name: "index_skill_versions_on_skill_id"
    t.index ["update_proposal_id"], name: "index_skill_versions_on_update_proposal_id"
  end

  create_table "skills", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by"
    t.boolean "builtin", default: false, null: false
    t.string "category"
    t.string "checksum"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.jsonb "declared_capabilities", default: {}, null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.text "proposal_notes"
    t.datetime "proposal_rejected_at"
    t.bigint "proposal_rejected_by"
    t.string "proposal_status"
    t.datetime "proposed_at"
    t.bigint "proposed_by_agent_id"
    t.jsonb "security_scan_result", default: {}, null: false
    t.string "source", default: "manual", null: false
    t.string "source_url"
    t.string "summary"
    t.text "tags", default: [], array: true
    t.string "tier", default: "manual", null: false
    t.text "trigger_patterns", default: [], array: true
    t.datetime "updated_at", null: false
    t.index ["checksum"], name: "index_skills_on_checksum"
    t.index ["enabled"], name: "index_skills_on_enabled"
    t.index ["name"], name: "index_skills_on_name", unique: true
    t.index ["proposal_status"], name: "index_skills_on_proposal_status"
    t.index ["proposed_by_agent_id"], name: "index_skills_on_proposed_by_agent_id"
    t.index ["source"], name: "index_skills_on_source"
    t.index ["tags"], name: "index_skills_on_tags", using: :gin
    t.index ["tier"], name: "index_skills_on_tier"
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

  create_table "task_attachments", force: :cascade do |t|
    t.string "content_type"
    t.datetime "created_at", null: false
    t.bigint "task_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "uploaded_by"
    t.string "url", null: false
    t.index ["task_id"], name: "index_task_attachments_on_task_id"
  end

  create_table "task_dependencies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "depends_on_id", null: false
    t.bigint "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["depends_on_id"], name: "index_task_dependencies_on_depends_on_id"
    t.index ["task_id", "depends_on_id"], name: "index_task_dependencies_on_task_id_and_depends_on_id", unique: true
    t.index ["task_id"], name: "index_task_dependencies_on_task_id"
  end

  create_table "task_events", force: :cascade do |t|
    t.bigint "agent_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "summary", null: false
    t.bigint "task_id", null: false
    t.index ["agent_id"], name: "index_task_events_on_agent_id"
    t.index ["task_id", "created_at"], name: "index_task_events_on_task_id_and_created_at"
    t.index ["task_id"], name: "index_task_events_on_task_id"
  end

  create_table "task_hooks", force: :cascade do |t|
    t.bigint "agent_id"
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "on_status", null: false
    t.integer "position", default: 0, null: false
    t.bigint "skill_id"
    t.bigint "task_id"
    t.bigint "task_template_id"
    t.bigint "team_id"
    t.string "trigger", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_task_hooks_on_agent_id"
    t.index ["skill_id"], name: "index_task_hooks_on_skill_id"
    t.index ["task_id", "trigger", "on_status"], name: "index_task_hooks_on_task_id_and_trigger_and_on_status"
    t.index ["task_id"], name: "index_task_hooks_on_task_id"
    t.index ["task_template_id", "trigger", "on_status"], name: "index_task_hooks_on_task_template_id_and_trigger_and_on_status"
    t.index ["task_template_id"], name: "index_task_hooks_on_task_template_id"
    t.index ["team_id", "trigger", "on_status"], name: "index_task_hooks_on_team_id_and_trigger_and_on_status"
    t.index ["team_id"], name: "index_task_hooks_on_team_id"
  end

  create_table "task_templates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "default_metadata", default: {}, null: false
    t.string "default_priority", default: "medium", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_task_templates_on_name", unique: true
  end

  create_table "tasks", force: :cascade do |t|
    t.datetime "archived_at"
    t.jsonb "artifacts", default: [], null: false
    t.bigint "assigned_to_agent_id"
    t.jsonb "checklist", default: [], null: false
    t.jsonb "comments", default: [], null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "created_by_agent_id"
    t.text "description"
    t.datetime "due_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "priority", default: "medium", null: false
    t.bigint "project_id"
    t.bigint "project_milestone_id"
    t.bigint "session_id"
    t.string "status", default: "backlog", null: false
    t.bigint "task_template_id"
    t.string "title", null: false
    t.datetime "transition_locked_at"
    t.bigint "transition_locked_by_agent_id"
    t.datetime "updated_at", null: false
    t.index ["archived_at"], name: "index_tasks_on_archived_at"
    t.index ["assigned_to_agent_id", "status"], name: "index_tasks_on_assigned_to_agent_id_and_status"
    t.index ["assigned_to_agent_id"], name: "index_tasks_on_assigned_to_agent_id"
    t.index ["created_at"], name: "index_tasks_on_created_at"
    t.index ["created_by_agent_id"], name: "index_tasks_on_created_by_agent_id"
    t.index ["priority"], name: "index_tasks_on_priority"
    t.index ["project_id"], name: "index_tasks_on_project_id"
    t.index ["project_milestone_id"], name: "index_tasks_on_project_milestone_id"
    t.index ["session_id"], name: "index_tasks_on_session_id"
    t.index ["status"], name: "index_tasks_on_status"
    t.index ["task_template_id"], name: "index_tasks_on_task_template_id"
    t.index ["transition_locked_at"], name: "index_tasks_on_transition_locked_at"
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
    t.text "raw_output"
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
    t.jsonb "required_credentials", default: []
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
    t.jsonb "request_payload"
    t.bigint "session_id"
    t.bigint "team_id"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "created_at"], name: "index_usage_records_on_agent_id_and_created_at"
    t.index ["agent_id"], name: "index_usage_records_on_agent_id"
    t.index ["created_at"], name: "index_usage_records_on_created_at"
    t.index ["session_id"], name: "index_usage_records_on_session_id"
    t.index ["team_id", "created_at"], name: "index_usage_records_on_team_id_and_created_at"
    t.index ["team_id"], name: "index_usage_records_on_team_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.jsonb "notification_preferences", default: {"budget_alerts" => true, "agent_responses" => true, "task_completions" => true, "heartbeat_findings" => false}, null: false
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
    t.string "tool_binding"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "namespace", "key"], name: "idx_vault_unique_entry", unique: true
    t.index ["agent_id"], name: "index_vault_entries_on_agent_id"
    t.index ["tool_binding"], name: "index_vault_entries_on_tool_binding"
  end

  create_table "webhook_endpoints", force: :cascade do |t|
    t.bigint "agent_id"
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.jsonb "event_types", default: [], null: false
    t.integer "failure_count", default: 0, null: false
    t.datetime "last_delivered_at"
    t.integer "last_status"
    t.text "secret"
    t.bigint "team_id"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["agent_id"], name: "index_webhook_endpoints_on_agent_id"
    t.index ["enabled"], name: "index_webhook_endpoints_on_enabled"
    t.index ["event_types"], name: "index_webhook_endpoints_on_event_types", using: :gin
    t.index ["team_id"], name: "index_webhook_endpoints_on_team_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_budgets", "agents"
  add_foreign_key "agent_channels", "agents"
  add_foreign_key "agent_channels", "channels"
  add_foreign_key "agent_mcp_servers", "agents"
  add_foreign_key "agent_mcp_servers", "mcp_servers"
  add_foreign_key "agent_skills", "agents"
  add_foreign_key "agent_skills", "skills"
  add_foreign_key "agent_tools", "agents"
  add_foreign_key "agent_tools", "tools"
  add_foreign_key "agents", "agents", column: "reports_to_id", on_delete: :nullify
  add_foreign_key "agents", "teams"
  add_foreign_key "api_integrations", "users"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "approval_requests", "agents"
  add_foreign_key "channel_threads", "agents"
  add_foreign_key "channel_threads", "channels"
  add_foreign_key "chat_attachments", "sessions"
  add_foreign_key "coding_agent_tasks", "agents"
  add_foreign_key "coding_agent_tasks", "sessions"
  add_foreign_key "delivery_queue_entries", "agents"
  add_foreign_key "delivery_queue_entries", "channels"
  add_foreign_key "delivery_queue_entries", "sessions"
  add_foreign_key "heartbeat_runs", "agents"
  add_foreign_key "heartbeat_runs", "sessions"
  add_foreign_key "inbound_messages", "channels"
  add_foreign_key "knowledge_chunks", "agents"
  add_foreign_key "knowledge_chunks", "knowledge_documents"
  add_foreign_key "knowledge_documents", "agents"
  add_foreign_key "memory_entries", "agents"
  add_foreign_key "memory_entries", "memory_entries", column: "superseded_by_id"
  add_foreign_key "outbound_messages", "channels"
  add_foreign_key "project_events", "agents"
  add_foreign_key "project_events", "project_milestones"
  add_foreign_key "project_events", "projects"
  add_foreign_key "project_events", "users"
  add_foreign_key "project_milestones", "agents"
  add_foreign_key "project_milestones", "projects"
  add_foreign_key "project_milestones", "sessions"
  add_foreign_key "projects", "agents", column: "lead_agent_id"
  add_foreign_key "projects", "teams"
  add_foreign_key "projects", "users"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "research_sessions", "agents"
  add_foreign_key "research_sessions", "sessions"
  add_foreign_key "scheduled_tasks", "agents"
  add_foreign_key "sessions", "agents"
  add_foreign_key "sessions", "team_chat_sessions"
  add_foreign_key "skill_load_events", "agents"
  add_foreign_key "skill_load_events", "sessions"
  add_foreign_key "skill_load_events", "skills"
  add_foreign_key "skill_tools", "skills"
  add_foreign_key "skill_tools", "tools"
  add_foreign_key "skill_update_proposals", "agents", column: "proposed_by_agent_id"
  add_foreign_key "skill_update_proposals", "skills"
  add_foreign_key "skill_versions", "skills"
  add_foreign_key "skills", "agents", column: "proposed_by_agent_id", on_delete: :nullify
  add_foreign_key "sub_agent_tasks", "agents", column: "child_agent_id"
  add_foreign_key "sub_agent_tasks", "agents", column: "parent_agent_id"
  add_foreign_key "sub_agent_tasks", "sessions", column: "child_session_id"
  add_foreign_key "sub_agent_tasks", "sessions", column: "parent_session_id"
  add_foreign_key "task_attachments", "tasks"
  add_foreign_key "task_dependencies", "tasks"
  add_foreign_key "task_dependencies", "tasks", column: "depends_on_id"
  add_foreign_key "task_events", "agents"
  add_foreign_key "task_events", "tasks"
  add_foreign_key "task_hooks", "agents"
  add_foreign_key "task_hooks", "skills"
  add_foreign_key "task_hooks", "task_templates"
  add_foreign_key "task_hooks", "tasks"
  add_foreign_key "task_hooks", "teams"
  add_foreign_key "tasks", "agents", column: "assigned_to_agent_id"
  add_foreign_key "tasks", "agents", column: "created_by_agent_id"
  add_foreign_key "tasks", "agents", column: "transition_locked_by_agent_id"
  add_foreign_key "tasks", "project_milestones"
  add_foreign_key "tasks", "projects"
  add_foreign_key "tasks", "sessions"
  add_foreign_key "tasks", "task_templates"
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
  add_foreign_key "usage_records", "teams"
  add_foreign_key "vault_entries", "agents"
  add_foreign_key "webhook_endpoints", "agents"
  add_foreign_key "webhook_endpoints", "teams"
end
