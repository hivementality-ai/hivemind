# 🐝 Hivemind

**Multi-agent AI team platform.** Deploy a team of AI agents that collaborate, use tools, and connect to your messaging channels — fully self-hosted.

Built with Ruby on Rails 8 · PostgreSQL · Redis · Sidekiq · Docker

[![Ruby](https://img.shields.io/badge/Ruby-3.4.8-red)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/Rails-8.0-red)](https://rubyonrails.org/)
[![License](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

---

## Why Hivemind?

Most AI platforms give you **one agent in a chat box**. Hivemind gives you a **team**.

- 🤖 **Multiple specialized agents** working together — a software engineer, a tester, a researcher, each with their own tools and personality
- 🔗 **Any channel** — Telegram, Discord, Slack, WhatsApp, Signal, or the built-in web chat
- 🔒 **Self-hosted** — your data stays on your hardware, API keys encrypted in a vault
- 🐳 **One command to run** — `docker compose up` and you're live
- 💰 **Cost controls** — per-agent budgets with alerts and auto-pause
- 👁️ **Mission Control** — real-time dashboard showing what every agent is doing

---

## Quick Start

### Prerequisites

- [Docker Desktop](https://docs.docker.com/get-docker/) (or Docker Engine + Compose v2)
- An API key from at least one provider:
  - [Anthropic](https://console.anthropic.com/) (Claude) — recommended
  - [OpenAI](https://platform.openai.com/) (GPT)
  - [Ollama](https://ollama.com/) (local models, free)

### Get running in 3 steps

```bash
# 1. Clone
git clone https://github.com/your-org/hivemind.git
cd hivemind

# 2. Configure (add at least one API key)
cp .env.example .env
nano .env

# 3. Launch
docker compose up -d
```

Open **[http://localhost:3000](http://localhost:3000)** — the setup wizard walks you through creating your account, connecting a provider, and deploying your first agent.

> First boot takes 2–3 minutes to build images. After that, starts in seconds.

---

## Setup Wizard

On first launch, Hivemind walks you through a 4-step setup — no config files, no CLI:

| Step | What happens |
|------|-------------|
| **1. Account** | Create the owner account (email + password) |
| **2. Provider** | Paste an API key — Anthropic, OpenAI, or Ollama URL |
| **3. Team** | Name your first agent team |
| **4. Agent** | Pick a template and deploy your first agent |

After setup, you land in **Mission Control** — the real-time dashboard for your agent team.

---

## Features

### 🤖 Agent Teams
Agents aren't solo — they work together. Group agents into teams with shared context, internal messaging, and task delegation. An orchestrator agent can decompose complex tasks and route work to specialists.

### 👁️ Mission Control
Real-time dashboard showing every agent's status, current task, live tool calls (via ActionCable), token spend, and conversation transcripts. Mobile-responsive.

### 🧩 Agent Templates
Deploy pre-built agent personas in one click:

| Template | What it does |
|----------|-------------|
| 👨‍💻 **Software Engineer** | Clones repos, writes code, runs tests, opens PRs |
| 🧪 **Software Tester** | Writes comprehensive test suites, finds edge cases |
| 🔍 **Code Reviewer** | Reviews PRs, catches bugs, suggests improvements |
| 📊 **Research Analyst** | Deep web research with cited reports |
| ⚙️ **DevOps Engineer** | Infrastructure, CI/CD, monitoring |
| 📝 **Technical Writer** | Documentation, READMEs, tutorials |
| 📈 **Data Analyst** | SQL queries, data exploration, visualizations |
| 🔒 **Security Auditor** | Vulnerability scanning, OWASP compliance |
| 📋 **Project Manager** | Task breakdown, coordination, status reports |
| ✨ **Creative Writer** | Marketing copy, blog posts, social content |

Create custom templates with your own system prompt, model config, tools, and SOUL.md personality.

### 🔗 Multi-Channel
Connect agents to the platforms your team already uses:

| Channel | Method | Status |
|---------|--------|--------|
| **Web Chat** | Built-in (ActionCable) | ✅ Ready |
| **Telegram** | Webhook | ✅ Ready |
| **Discord** | Bot/Webhook | ✅ Ready |
| **Slack** | Bot/Webhook | ✅ Ready |
| **WhatsApp** | Connector sidecar | 🔧 Scaffolded |
| **Signal** | Connector sidecar | 🔧 Scaffolded |

### 🛠️ Tools
Agents have access to a full toolkit:

| Tool | Capability |
|------|-----------|
| **File ops** | Read, write, edit files in the workspace |
| **Exec** | Run shell commands (git, tests, builds, scripts) |
| **Browser** | Playwright automation (headless Chrome) |
| **Web search** | Brave Search API |
| **Web fetch** | HTTP fetch with content extraction |
| **Memory** | Semantic search with pgvector embeddings |
| **Vault** | Read/write encrypted secrets |
| **Cron** | Create and manage scheduled jobs |
| **Message** | Send to channels, cross-agent messaging |
| **Platform** | Restart services, clear caches, check status |
| **Sessions** | Spawn sub-agents, view history |

### 💰 Cost Budgets
Set daily and monthly spend limits per agent. Warning at 80%, hard stop at 100%. Dashboard shows burn rate and projections. Never get a surprise bill.

### ✅ Approval Workflows
Configure which actions need human approval before execution. Approval requests route to the UI with approve/reject buttons and configurable timeouts.

### 📊 Analytics
Usage stats, response times, error rates, task completion tracking, and cost breakdowns per agent, model, and channel.

### 🔒 Security
- **Vault** — API keys and secrets encrypted at rest with ActiveRecord Encryption
- **Audit log** — append-only trail of every action (auth, vault, exec, messages)
- **Webhook HMAC** — all inbound webhooks verified with signatures
- **Rate limiting** — Rack::Attack on all endpoints
- **Workspace isolation** — agent code runs in a separate container, no access to DB or Redis
- **API tokens** — scoped with JSONB permissions, revocable

---

## Architecture

```
                         ┌──────────────────┐
     Telegram ──────────▶│                  │
     Discord  ──────────▶│    Rails App     │◀──── Mission Control UI
     Slack    ──────────▶│  (API + Cable)   │◀──── REST API
     Webhooks ──────────▶│                  │
                         └────────┬─────────┘
                                  │
                 ┌────────────────┼────────────────┐
                 ▼                ▼                 ▼
           ┌──────────┐    ┌──────────┐     ┌───────────┐
           │ Postgres  │    │  Redis   │     │  Sidekiq  │
           │ (pgvector)│    │  7-alp   │     │  workers  │
           └──────────┘    └──────────┘     └───────────┘
                 ┌────────────────┼────────────────┐
                 ▼                ▼                 ▼
           ┌──────────┐    ┌──────────┐     ┌───────────┐
           │Workspace  │    │ Browser  │     │ Connector │
           │(git,code) │    │Playwright│     │ WA/Signal │
           └──────────┘    └──────────┘     └───────────┘
```

### Docker Compose Stack (7 containers)

| Container | Image | Purpose | Network |
|-----------|-------|---------|---------|
| **rails** | Custom (Ruby 3.4.8) | Web app, API, ActionCable | internal, web |
| **sidekiq** | Same as rails | Background jobs, cron, budgets | internal |
| **postgres** | pgvector/pgvector:pg17 | Database with vector extensions | internal |
| **redis** | redis:7-alpine | Job queue, pub/sub, cache | internal |
| **workspace** | Ubuntu 24.04 | Agent code execution sandbox | web |
| **browser** | Playwright | Headless browser for agents | internal, web |
| **connector** | Custom (Ruby) | WhatsApp/Signal bridge | internal, web |

### Network Isolation

- **`internal`** — Rails, Sidekiq, Postgres, Redis, Connector. The trusted core.
- **`web`** — Rails, Workspace, Browser, Connector. Internet-facing services.
- Workspace has full internet access (git clone, npm install, API calls) but **cannot reach the database or Redis**.

### How Agent Execution Works

1. Message arrives (webhook, API, or web chat)
2. Rails routes to the target agent's session
3. Agent runtime assembles context (transcript history, system prompt, tools)
4. LLM provider called (Anthropic/OpenAI/Ollama) with streaming
5. If the LLM requests a tool call → routed to the appropriate executor:
   - **File/web/memory** → runs in the Rails process
   - **Shell/git/code** → runs in the Workspace container
   - **Browser** → runs in the Playwright container
6. Tool result fed back to LLM for next step
7. Final response streamed to the user via ActionCable
8. Transcript persisted, usage recorded, costs tracked

---

## Database Schema

### 21 Tables

| Category | Tables |
|----------|--------|
| **Core** | `users`, `api_tokens`, `teams`, `agents`, `sessions`, `transcript_archives` |
| **Security** | `vault_entries`, `audit_logs`, `device_pairings` |
| **Messaging** | `channels`, `team_messages`, `inbound_messages`, `outbound_messages` |
| **Scheduling** | `scheduled_tasks` |
| **Analytics** | `usage_records`, `agent_budgets` |
| **Config** | `settings`, `provider_configs`, `agent_templates` |
| **Memory** | `memory_entries` (with pgvector embeddings) |
| **Approvals** | `approval_requests` |

---

## Project Structure

```
hivemind/
├── app/
│   ├── controllers/
│   │   ├── setup_controller.rb        # First-run setup wizard
│   │   ├── dashboard_controller.rb    # Mission Control
│   │   ├── agents_controller.rb       # Agent CRUD
│   │   ├── agent_templates_controller.rb
│   │   ├── analytics_controller.rb
│   │   ├── budgets_controller.rb
│   │   ├── platform_controller.rb     # System status/restart
│   │   ├── webhooks_controller.rb     # Inbound channel webhooks
│   │   └── api/v1/                    # REST API
│   ├── models/                        # 22 models
│   ├── services/
│   │   ├── agents/                    # Delegate, Orchestrate, Communicate, Handoff
│   │   ├── analytics/                 # AgentSummary, TeamSummary
│   │   ├── approvals/                 # Request, Resolve
│   │   ├── audit/                     # Record (async via Sidekiq)
│   │   ├── budgets/                   # Check, RecordSpend
│   │   ├── channels/                  # Telegram, Discord, Slack, WhatsApp, Signal adapters
│   │   ├── memory/                    # Store, Search (pgvector)
│   │   ├── platform/                  # RestartService, ContainerStatus, ClearCache
│   │   ├── providers/                 # OpenAI, Anthropic, Ollama adapters + Resolver
│   │   └── vault/                     # Read, Write (encrypted)
│   ├── sidekiq/                       # AgentTaskJob, AuditLogJob, BudgetReset/Alert
│   ├── views/
│   │   ├── setup/                     # 4-step setup wizard
│   │   ├── dashboard/                 # Mission Control
│   │   ├── agents/                    # Agent CRUD views
│   │   ├── agent_templates/           # Template gallery
│   │   ├── analytics/                 # Usage dashboards
│   │   └── layouts/                   # Dark theme (Tailwind bg-gray-900)
│   └── javascript/controllers/        # Stimulus (sidebar, template picker)
├── config/
│   ├── routes.rb
│   ├── sidekiq.yml
│   └── connector.yml
├── db/
│   ├── migrate/                       # All migrations
│   └── seeds/
│       └── agent_templates.rb         # 10 pre-built templates
├── lib/
│   └── connector/                     # WhatsApp/Signal sidecar
├── docs/
│   └── steering/                      # Code standards, testing strategy
├── docker-compose.yml                 # 7-container production stack
├── Dockerfile                         # Rails app (multi-stage)
├── Dockerfile.workspace               # Agent sandbox (Ubuntu 24.04)
├── Dockerfile.connector               # Channel bridge
└── .env.example                       # Configuration template
```

---

## API

All API endpoints require a Bearer token (create one in Mission Control → Settings).

### Agents

```bash
# List agents
curl http://localhost:3000/api/v1/agents \
  -H "Authorization: Bearer hv_your_token"

# Create an agent
curl -X POST http://localhost:3000/api/v1/agents \
  -H "Authorization: Bearer hv_your_token" \
  -H "Content-Type: application/json" \
  -d '{
    "agent": {
      "name": "My Agent",
      "role": "assistant",
      "provider": "anthropic",
      "model": "claude-sonnet-4",
      "system_prompt": "You are a helpful assistant."
    }
  }'
```

### Sessions

```bash
# Send a message to an agent
curl -X POST http://localhost:3000/api/v1/sessions \
  -H "Authorization: Bearer hv_your_token" \
  -H "Content-Type: application/json" \
  -d '{"agent_id": 1, "message": "Hello!"}'

# Get session history
curl http://localhost:3000/api/v1/sessions/1 \
  -H "Authorization: Bearer hv_your_token"
```

---

## Local Development

Run Rails natively if you prefer (no Docker needed for dev):

```bash
# Prerequisites: Ruby 3.4.8 (rbenv), PostgreSQL 17, Redis 7

# Install dependencies
bundle install

# Setup database
bin/rails db:prepare
bin/rails db:seed

# Start Rails + Sidekiq + CSS watcher
bin/dev
```

For agent execution features, start the workspace and browser containers:

```bash
docker compose up workspace browser -d
```

### Running Tests

```bash
# Full suite
bundle exec rspec

# Specific file
bundle exec rspec spec/models/agent_spec.rb

# With coverage report
COVERAGE=true bundle exec rspec
```

---

## Configuration

### Environment Variables

See [`.env.example`](.env.example) for the full list with documentation.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | One provider needed | — | Anthropic (Claude) API key |
| `OPENAI_API_KEY` | One provider needed | — | OpenAI (GPT) API key |
| `OLLAMA_URL` | One provider needed | — | Ollama endpoint (no key) |
| `RAILS_MASTER_KEY` | Auto-generated | `config/master.key` | Decrypts Rails credentials |
| `DATABASE_URL` | Docker sets this | — | PostgreSQL connection string |
| `REDIS_URL` | Docker sets this | — | Redis connection string |
| `RAILS_MAX_THREADS` | No | `5` | Puma/Sidekiq concurrency |
| `RAILS_LOG_LEVEL` | No | `info` | Log verbosity |

### Channel Setup

Channel API keys are stored in the encrypted vault (Mission Control → Settings → Vault):

| Channel | What you need | Where to get it |
|---------|--------------|-----------------|
| **Telegram** | Bot token | [@BotFather](https://t.me/BotFather) |
| **Discord** | Bot token | [Developer Portal](https://discord.com/developers) |
| **Slack** | Bot token + signing secret | [api.slack.com](https://api.slack.com/apps) |
| **WhatsApp** | Connector container | Business API or Baileys |
| **Signal** | Connector container | signal-cli |

### AI Providers

| Provider | Models | Cost | Setup |
|----------|--------|------|-------|
| **Anthropic** | Claude Haiku, Sonnet, Opus | Pay per token | API key |
| **OpenAI** | GPT-4o, GPT-5, o-series | Pay per token | API key |
| **Ollama** | Llama, Mistral, Gemma, etc. | Free (local) | Install Ollama, pull a model |

---

## Operations

```bash
# Start all containers
docker compose up -d

# View logs
docker compose logs -f              # All
docker compose logs rails -f        # Just Rails
docker compose logs sidekiq -f      # Just Sidekiq

# Check container health
docker compose ps

# Restart a specific service
docker compose restart rails

# Open a Rails console
docker compose exec rails bin/rails console

# Run a migration
docker compose exec rails bin/rails db:migrate

# Rebuild after code changes
docker compose build && docker compose up -d

# Stop everything (keep data)
docker compose down

# Nuclear reset (wipe all data)
docker compose down -v
```

---

## Code Standards

Hivemind follows strict Rails conventions (see `docs/steering/` for full guides):

- **Skinny controllers** — parse params, authorize, call service, render
- **Service objects** — keyword args, always return `ServiceResponse`
- **Models** — associations, validations, scopes, simple domain logic only
- **RSpec** — 95% coverage target, no system/view tests, `build` over `create`
- **FactoryBot** — traits for variations, sequences for uniqueness
- **Tailwind CSS** — dark theme (bg-gray-900), responsive-first

### ServiceResponse Pattern

Every service returns a `ServiceResponse`:

```ruby
# In a service
class Vault::Read
  def self.call(namespace:, key:, agent: nil)
    entry = VaultEntry.resolve(namespace:, key:, agent:)
    return ServiceResponse.failure(error: "Key not found") unless entry

    ServiceResponse.success(data: { value: entry.encrypted_value })
  end
end

# In a controller
result = Vault::Read.call(namespace: "providers", key: "anthropic_api_key")
if result.success?
  render json: result.data
else
  render json: { error: result.error }, status: :not_found
end
```

---

## Roadmap

- [x] Core scaffold (models, services, auth, Docker)
- [x] Agent teams with delegation and orchestration
- [x] Multi-channel adapters (Telegram, Discord, Slack)
- [x] Mission Control dashboard
- [x] Agent templates with gallery
- [x] Cost budgets and analytics
- [x] Setup wizard (first-run onboarding)
- [ ] **Agent runtime** — the core LLM orchestration loop
- [ ] RSpec test suite (95% coverage)
- [ ] pgvector memory search integration
- [ ] WhatsApp/Signal real integration (connector sidecar)
- [ ] ActionCable live streaming in Mission Control
- [ ] GitHub push + CI/CD pipeline
- [ ] Agent template marketplace

---

## Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. Write tests first (or alongside)
4. Follow the service object pattern and code standards
5. `bundle exec rspec` — all green
6. `bundle exec rubocop` — no offenses
7. Open a PR with a clear description

---

## License

[MIT](LICENSE)

---

<p align="center">
  <strong>🐝 Deploy your AI team in minutes, not months.</strong>
</p>
