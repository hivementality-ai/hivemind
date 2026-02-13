# Hivemind 🐝

## Overview
A multi-channel AI agent team platform built in **Ruby 3.4.8 / Rails 8**. Coordinate a hive of specialized AI agents through any messaging channel with real-time observability, security-first design, and Docker-native production deployment. PostgreSQL + Redis + Sidekiq.

---

## Stack
- **Ruby** 3.4.8
- **Rails** 8
- **Database:** PostgreSQL (pgcrypto, pgvector for embeddings)
- **Cache/Queues:** Redis
- **Background Jobs:** Sidekiq + sidekiq-cron
- **WebSocket:** ActionCable
- **Auth:** Devise + custom API tokens
- **Docker:** Production-only, multi-container architecture

---

## Docker Compose Stack

| Container | Purpose |
|-----------|---------|
| **rails** | Puma + ActionCable (HTTP, WebSocket, API) |
| **sidekiq** | Background jobs (agent runs, cron, audit, archival) |
| **postgres** | Primary database |
| **redis** | Sidekiq queues + ActionCable pub/sub + caching |
| **browser** | Playwright + headless Chrome |
| **workspace** | Exec sandbox (agent shell access, full internet) |
| **connector** | Persistent channel connections (WhatsApp, Signal) |

---

## Security Decisions (Locked)

### 1. Secrets Management
- `Rails.credentials` for infrastructure (DB, Redis, master key)
- `vault_entries` table with ActiveRecord Encryption for dynamic secrets
- Scoped by agent + namespace + key
- Agent reads actual values via `vault` tool
- Redacted from transcripts/logs/chat output
- Every access hits audit log

### 2. Authentication & Authorization
- Devise for user auth (web UI)
- `api_tokens` table with `scopes` JSONB (simple now, medium RBAC later)
- Simple mode: owner full access, tokens full or readonly
- Device pairing backed by DB
- Upgrade path to per-agent scoping built in

### 3. Session Transcript Storage
- `sessions` table with metadata + `transcript` JSONB array
- Agent queries its own history directly from DB
- Archival job moves bloated transcripts to `transcript_archives` when threshold exceeded
- Encrypted at rest via PostgreSQL

### 4. Exec / Tool Sandboxing
- Workspace container with full shell access — isolated from app/db/redis
- Network access for internet (outbound only)
- No access to internal services
- Resource limits enforced (CPU/mem/time)
- Rebuildable/disposable
- File ops and web fetch run in Rails app
- Browser in its own container (Playwright + headless Chrome)

### 5. Webhook Security
- Channel webhook secrets stored in vault table
- HMAC verification enforced on all inbound webhooks
- Timestamp validation (reject stale requests)
- Rack::Attack rate limiting per IP and per endpoint
- Custom hooks get our own HMAC scheme
- Leverage gem-level verification where available

### 6. Audit Logging
- `audit_logs` table: actor, action, resource, metadata, timestamp
- Append-only — no updates, no deletes
- Async writes via Sidekiq
- Sensitive values redacted
- Retention policy: configurable, default 90 days
- Covers: auth, vault, exec, messages, config, webhooks, sessions

### 7. Connector Sidecar
- Thin daemon for persistent channel connections (WhatsApp/Baileys, Signal)
- Feeds messages into Rails via Redis or internal HTTP
- Sends outbound messages on request
- Separate container, stateless (connection state in Redis/DB)

---

## Core Features

### Agent Teams 🤝
- **Roles** — each agent has a defined role (coder, researcher, devops, writer, lead)
- **Team channels** — shared internal message bus (`team_messages` table, surfaced in UI)
- **Task delegation** — agents assign work to each other, spawns background jobs
- **Shared memory** — team-level knowledge base alongside per-agent memory (pgvector)
- **Orchestrator pattern** — optional "lead" agent that decomposes tasks and coordinates
- **Conversation handoff** — mid-conversation transfer to specialist with full context

### Live Activity UI (Mission Control) 👁️
- **Agent cards** — every agent's status (idle/thinking/executing/waiting), current task
- **Live tool stream** — real-time tool calls scrolling by (ActionCable)
- **Token/cost ticker** — live spend per agent, per session
- **Transcript view** — click into any agent's conversation, watch it unfold live
- **Timeline** — visual history across all agents
- **Mobile-responsive** — works great on phones

### Agent-Managed Cron ⏰
- `sidekiq_cron` tool — agents CRUD scheduled jobs
- `scheduled_tasks` table (agent_id, schedule, job_class, params, enabled)
- Agent writes job logic as scripts in workspace, Sidekiq runs on schedule
- Jobs execute inside workspace container (sandboxed)

### Self-Management 🔄
- `platform` tool — restart services, rebuild containers, clear caches
- Deploy config changes at runtime
- Cannot touch Postgres or Redis directly, only through defined actions

### Cost Budgets 💰
- Per-agent daily/monthly spend limits on LLM calls
- Warning at 80%, hard stop at 100%
- Dashboard shows burn rate and projections
- Budget configuration per agent

### Approval Workflows 🔀
- Configurable: which actions need approval, which are auto-approved
- Routes to user (or lead agent) for approval
- UI notifications with approve/reject buttons
- Approval timeout with configurable default action

### Agent Analytics 📊
- Usage stats: which agents get used most, response times, error rates
- Task completion tracking and success rates
- Cost breakdown per agent/model/channel
- Weekly/monthly reports

### Agent Templates 🧩
- Pre-built personas deployable in one click
- Includes: SOUL.md, tools config, model config, role definition
- Community-contributed template marketplace (future)
- "Add a Code Reviewer" → fully configured agent in seconds

### Mobile Dashboard 📱
- Responsive design from day one
- Check agent team status from phone
- Approve actions, read transcripts, see costs
- Push notifications for approvals and alerts

---

## Channel Support (Priority Order)

### Phase 1 (Webhook-based, straightforward)
- WebChat (built-in, ActionCable)
- Telegram (webhook)
- Discord (webhook/bot)
- Slack (webhook/bot)

### Phase 2
- WhatsApp (connector sidecar + Baileys or Business API)
- Signal (connector sidecar)

### Phase 3
- iMessage
- Google Chat
- MS Teams
- IRC
- LINE

---

## Models / Providers

### Provider Interface
All providers implement a common adapter interface:
- `chat(messages, tools, options)` → streaming response
- `models()` → list available models
- `embed(text)` → vector embedding (for memory search)

### Supported Providers (MVP)
1. **OpenAI** — GPT-4o, GPT-5, o-series. API key stored in vault.
2. **Anthropic** — Haiku, Sonnet, Opus. API key stored in vault.
3. **Local (Ollama)** — Any GGUF model via Ollama. No API key, just base URL (default `http://localhost:11434`). Free, private, runs on user's hardware.

### Future Providers (extensible adapter pattern)
- Google Gemini, AWS Bedrock, Azure OpenAI, Groq, Together, OpenRouter

### Provider Config
- `provider_configs` table: name, adapter_type, base_url, auth (vault reference), enabled
- Per-agent model selection: primary + fallback chain
- User chooses default provider per agent, can mix (e.g., Opus for coding, Haiku for chat, local for heartbeats)
- Cost tracking per request (input/output/cache tokens with per-model pricing)
- Model failover with ordered fallbacks
- Local models have zero cost tracking (free)

---

## Tools (Agent Capabilities)
- **File ops:** read, write, edit (workspace volume)
- **Exec:** shell commands (workspace container)
- **Browser:** Playwright automation (browser container)
- **Web:** search (Brave API), fetch (HTTP)
- **Memory:** search (pgvector), read/write markdown
- **Vault:** get/set/list/delete encrypted secrets
- **Cron:** CRUD Sidekiq scheduled jobs
- **Message:** send to channels, cross-agent messaging
- **Platform:** restart services, config changes
- **Sessions:** list, history, spawn sub-agents
- **Image:** vision model analysis
- **TTS:** text-to-speech

---

## Database Schema (Key Tables)

### Core
- `users` — Devise auth, roles
- `api_tokens` — scoped API keys with expiry
- `agents` — id, name, role, model config, workspace path, team_id
- `teams` — agent team grouping
- `sessions` — key, agent_id, metadata, transcript (JSONB), tokens, timestamps
- `transcript_archives` — archived session transcripts

### Security
- `vault_entries` — encrypted key-value store (agent_id, namespace, key, encrypted_value)
- `audit_logs` — append-only audit trail
- `device_pairings` — node device registration and approval

### Messaging
- `channels` — configured messaging channels (type, config, webhook secrets)
- `team_messages` — inter-agent communication bus
- `inbound_messages` — raw inbound message log
- `outbound_messages` — raw outbound message log

### Scheduling
- `scheduled_tasks` — agent-managed cron jobs

### Analytics
- `usage_records` — per-request token/cost tracking
- `agent_budgets` — spending limits per agent

### Config
- `settings` — dynamic application settings (key-value)
- `provider_configs` — LLM provider definitions
- `model_definitions` — model metadata and pricing

---

## Phasing

### Phase 1 — MVP (Core Loop)
- Rails 8 scaffold + Docker Compose
- User auth (Devise) + API tokens
- Agent model + basic CRUD
- Vault table + ActiveRecord Encryption
- Session model with JSONB transcripts
- Agent runtime (LLM call → tool execution → response)
- Core tools: file ops, exec (workspace container), web search/fetch
- WebChat channel (ActionCable)
- Audit logging
- Basic UI: agent list, chat interface, activity stream
- Sidekiq + sidekiq-cron
- Cost tracking

### Phase 2 — Teams & Channels
- Multi-agent teams with delegation and shared memory
- Team message bus
- Orchestrator pattern
- Telegram + Discord + Slack channels
- Live Mission Control UI
- Agent-managed cron
- Approval workflows
- pgvector memory search

### Phase 3 — Scale & Polish
- WhatsApp + Signal (connector sidecar)
- Agent templates + marketplace
- Cost budgets with enforcement
- Agent analytics dashboard
- Mobile-responsive UI
- Conversation handoff
- Self-management tools
- Community features

---

## Code Standards (see docs/steering/)

### Rails Best Practices
- **Skinny controllers** — HTTP orchestration only (parse params, authorize, call service, render)
- **Service objects** — keyword args only, always return `ServiceResponse`
- **Query objects** — reusable ActiveRecord retrieval patterns
- **Models** — associations, validations, simple domain logic only
- **Concerns** — shared behavior with clear single responsibility
- **Explicit > implicit** — readability and clarity always

### Testing (RSpec)
- **95% overall coverage**, 100% diff coverage
- **90% branch coverage**
- Test public interface only, never private methods
- `describe` / `context` / `it` structure
- FactoryBot with traits, `build` over `create` when possible
- `instance_double` for external dependencies
- **No Capybara/system tests, no JS tests, no view tests**
- Controllers, models, services, queries, jobs, mailers all tested

### ServiceResponse Pattern
```ruby
ServiceResponse.success(data: { order: })
ServiceResponse.failure(error: "Something went wrong")
```

## Development Setup
- Local: `rails server` + `sidekiq` (no Docker required)
- Production: Docker Compose only
- CI: GitHub Actions (lint, test, build, push)

---

*Created: 2026-02-13*
*Status: Design locked, ready to build*
