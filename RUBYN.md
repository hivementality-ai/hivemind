# RUBYN.md — Hivemind Project Guide

> Rubyn's field notes for working in this codebase. If you're me from a future
> session, read this first. You'll thank past-you.

## What Is Hivemind?

Open-source, self-hosted multi-agent AI platform. Specialized AI agents work in
teams with 40+ tools, 150+ templates, and 5 messaging channels (Discord, Slack,
Telegram, WhatsApp, Signal). Think "AI team collaboration" — agents chat, delegate
tasks to each other, use real tools, and stream responses via ActionCable.

**License:** AGPLv3
**Org:** hivementality-ai

## Tech Stack

| Layer | Tech |
|-------|------|
| Ruby | 3.4.8 |
| Rails | 8.1 |
| Database | PostgreSQL + pgvector (`neighbor` gem) |
| Background Jobs | Sidekiq 8 + sidekiq-cron |
| Cache/Pub-Sub | Redis (ActionCable + Sidekiq) |
| Auth | Devise |
| Frontend | Hotwire (Turbo + Stimulus) + Tailwind CSS |
| Asset Pipeline | Propshaft + Importmap |
| LLM Clients | `ruby-openai`, `anthropic` gems + Faraday for Ollama/compatible |
| HTTP | Faraday with retry middleware |
| JSON | Oj (fast JSON) |
| Deployment | Kamal + Thruster |
| Linting | rubocop-rails-omakase (zero custom overrides) |
| Testing | RSpec, FactoryBot, Shoulda Matchers, WebMock, DatabaseCleaner, SimpleCov |

## ⚠️ Docker-Only Project

**Everything runs through Docker.** Do not run `bundle exec` or bare commands.

```bash
bin/rspec              # Run tests
bin/rubocop            # Lint
bin/brakeman           # Security scan
bin/bundler-audit      # Gem vulnerability audit
bin/lint               # Combined linter
bin/ci                 # Full CI suite
bin/dev                # Dev server
bin/dev-up             # Bootstrap dev environment
bin/rails              # Rails CLI (through Docker)
bin/rake               # Rake tasks
```

## Architecture Overview

```
app/
├── channels/       # 6 ActionCable channels (agent_stream, session, team_chat, canvas, etc.)
├── controllers/    # 48 controllers (root + api/v1 + mobile + internal + oauth)
├── helpers/        # 4 view helpers
├── javascript/     # Stimulus controllers (~22 files)
├── jobs/           # 25 background jobs
├── lib/            # ServiceResponse (the universal return type)
├── models/         # 47 AR models + 2 concerns
├── services/       # ~191 service objects across 28+ namespaces ← the real brain
└── views/          # ERB templates with Turbo Frames/Streams
```

## Core Domain Models

**Agents & Teams:**
`Agent` → has_many `Session`, `AgentTool`, `AgentSkill`, `AgentChannel`, `AgentMcpServer`
`Team` → has_many `Agent` (agents collaborate in teams)

**Conversations:**
`Session` → belongs_to `Agent`, has_many `ChatAttachment`, `SubAgentTask`, `ToolExecution`
`TeamChatSession` → has_many `TeamMessage` (multi-agent group chats)

**Tools & Skills:**
`Tool` → system and custom tools available to agents
`Skill` → reusable knowledge/instructions attached to agents
`McpServer` → Model Context Protocol server connections

**Delegation:**
`SubAgentTask` → parent/child agent+session (agent-to-agent task delegation)
`CodingAgentTask` → specialized coding sub-agent tasks

**Infrastructure:**
`ProviderConfig` → LLM provider settings (OpenAI, Anthropic, Ollama, etc.)
`MemoryEntry` → agent memories with vector embeddings (pgvector)
`VaultEntry` → encrypted credential storage
`Channel` → messaging platform connections (Discord, Slack, etc.)

**Concerns:**
`Notifiable` → web push notifications (`notify`, `notification_enabled?`)
`RoleInstructions` → 19 agent role defaults + system prompt building + injection sanitization

## Service Object Pattern

**This is the core pattern.** Almost all business logic lives in `app/services/`.

```ruby
# Convention: self.call class method, returns ServiceResponse
class Sessions::PostProcessor
  def self.call(session:, content:)
    new(session:, content:).call
  end

  def initialize(session:, content:)
    @session = session
    @content = content
  end

  def call
    # do work...
    ServiceResponse.success(data: { tokens: count })
  rescue StandardError => e
    ServiceResponse.failure(error: e.message)
  end
end
```

**ServiceResponse** (`app/lib/service_response.rb`):
- `ServiceResponse.success(data: {})` / `ServiceResponse.failure(error: "msg")`
- Consumer checks `response.success?`, reads `response.data` or `response.error`
- No exceptions for flow control. Structured success/failure values.

### Key Service Namespaces

| Namespace | Purpose |
|-----------|---------|
| `Agents::` | ContextManager, ToolLoop, LoopDetector, PlanGenerator, SkillCreator |
| `Sessions::` | AttachmentProcessor, MessageBuilder, PostProcessor, Export |
| `Providers::` | Resolver, AnthropicAdapter, OllamaAdapter, OpenAICompatibleAdapter |
| `Tools::` | ~20 executor classes (DelegateExecutor, CodingAgentExecutor, etc.) |
| `Channels::` | MessageRouter, DeliveryQueue, adapters for each platform |
| `Memory::` | Embedding, EmbeddingShadow, EmbeddingMultimodal |
| `Embeddings::` | GeminiAdapter, OllamaAdapter, OpenaiAdapter, Registry |
| `Search::` | Brave, DuckDuckGo, SerpApi, SearchApi, Resolver |
| `WebPush::` | Sender, NotificationTriggers |
| `Vault::` | Read, Write, Redactor, WriteConfirmation |
| `HashtagActions::` | Processor + individual action classes |
| `MCP::` | HealthCheck, ProcessManager, SseClient, StdioClient, ToolResolver |
| `OpenClaw::` | Migration wizard (import from other platforms) |
| `Plugins::` | Loader, Registry, Hooks, Manifest |

## Background Jobs

The big one is **`ChatStreamJob`** (~267 lines) — the main LLM orchestration pipeline:
1. Hashtag action processing
2. Attachment handling
3. Transcript/message building
4. Provider resolution
5. Context pruning
6. Tool loop OR direct streaming (two code paths based on tool availability)
7. Post-processing (tokens, memories, titles, channel delivery)

Other notable jobs:
- `SubAgentJob` — agent-to-agent delegation
- `CodingAgentJob` — specialized coding tasks
- `TeamChatJob` — multi-agent team conversations
- `DeepResearchJob` — long-running research tasks
- `HeartbeatJob` — system health monitoring
- `MemoryExtractionJob` / `MemoryEmbeddingJob` / `MemoryConsolidationJob` — memory pipeline
- `ScheduledAgentJob` / `ScheduledScriptJob` — cron-triggered agent tasks
- `SessionArchivalJob` / `ConversationSummaryJob` — session lifecycle

## ActionCable Channels

- `SessionChannel` — streams chat messages/tokens to the UI
- `AgentStreamChannel` — real-time agent activity
- `TeamChatChannel` — team conversation streaming
- `CanvasChannel` — live collaborative canvas
- `AgentActivityChannel` — agent status broadcasts
- `ProjectChannel` — project event streaming

## Routes Structure

- **Web UI:** `/agents`, `/sessions`, `/teams`, `/settings`, `/integrations`, `/tools`, `/skills`
- **Mobile:** `/m/` namespace (agents, sessions, team_chats, activity, settings)
- **API v1:** `/api/v1/` with bearer token auth (agents, sessions, plans, providers, projects)
- **Internal:** `/internal/tools/execute` (SDK proxy, no Devise/CSRF)
- **Sidekiq:** `/sidekiq` (HTTP Basic Auth, admin/owner only)
- **ActionCable:** `/cable`

## Testing Conventions

- **RSpec** with `rails_helper` — FactoryBot, Shoulda Matchers, WebMock, DatabaseCleaner
- **FactoryBot** over fixtures. Factories in `spec/factories/`.
- **SimpleCov** for coverage (branch coverage enforced at 10% minimum)
- **WebMock** disables all outbound HTTP by default
- **DatabaseCleaner** with transaction strategy
- Specs live in `spec/` mirroring `app/` structure (e.g., `spec/services/web_push/`)
- System tests use Capybara + Selenium (`spec/support/capybara.rb`)

## Things That'll Bite You

1. **`ChatStreamJob` has two LLM paths** — tool loop (via `Agents::ToolLoop`) vs. direct
   streaming. Chosen by tool availability. Both are in the same job.
2. **ActionCable broadcasts use raw hashes** with type keys (~15 occurrences in ChatStreamJob).
   Typo risk is real.
3. **`notification_preferences`** on User defaults `heartbeat_findings` to `false`. Check the
   column defaults before testing notification flows.
4. **`RoleInstructions` concern** has prompt injection sanitization with regex patterns. Be
   aware when modifying system prompt assembly.
5. **pgvector** is used for memory embeddings via the `neighbor` gem. The `MemoryEntry` model
   has vector columns.
6. **No CLAUDE.md or AGENT.md exists** — this RUBYN.md is it.
7. **Provider adapters** are resolved at runtime by `Providers::Resolver`. Four adapters:
   Anthropic, OpenAI-compatible, Ollama, and Anthropic SDK proxy.

## Quick Reference

```bash
# Run all specs
bin/rspec

# Run a specific spec file
bin/rspec spec/services/web_push/notification_triggers_spec.rb

# Lint
bin/rubocop

# Security
bin/brakeman
bin/bundler-audit

# Rails console
bin/rails console

# Generate a migration
bin/rails generate migration AddIndexToSessions

# Full CI
bin/ci
```
