<p align="center">
  <img src="public/brand/logo.svg" width="80" alt="Hivemind">
</p>

<h1 align="center">Hivemind</h1>

<p align="center">
  <strong>Multi-agent AI team platform.</strong><br>
  Deploy teams of AI agents that collaborate, use tools, and connect to your messaging channels.<br>
  Self-hosted. Open source.
</p>

<p align="center">
  <a href="https://discord.gg/Cww4rFz7"><img src="https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=flat&logo=discord&logoColor=white" alt="Discord"></a>
  <img src="https://img.shields.io/badge/Docker-Compose-2496ED?style=flat&logo=docker" alt="Docker">
  <img src="https://img.shields.io/badge/License-AGPLv3-blue?style=flat" alt="License">
</p>

---

## Why Hivemind?

Most AI platforms give you one agent in a chat box. Hivemind gives you a **team**.

- **Multiple specialized agents** with different models, roles, and tools
- **Team chat** with @mentions — agents collaborate and chain-react
- **34 built-in tools** — shell, files, browser, Jira, email, cloud storage, Gmail, vision, TTS, and more
- **Skills system** — teach agents new capabilities, import OpenClaw SKILL.md files
- **5 messaging channels** — Discord, Slack, Telegram, WhatsApp, Signal
- **Slack multi-bot** — each agent gets its own Slack bot identity with thread routing
- **Coding agent** — delegate complex tasks to Claude Code, Codex, or Aider with live progress streaming
- **File sharing** — agents create files and images, deliver them directly to chat
- **Autonomous heartbeat** — agents run periodic checks without you asking
- **Sub-agent orchestration** — delegate (sync), spawn (async), or team chat
- **Image support** — send images to agents, receive images back (vision API)
- **Cloud storage** — Google Drive, S3, Dropbox, OneDrive, B2, SFTP via rclone
- **Self-hosted** — your data stays on your hardware, API keys encrypted in vault
- **One command** — `docker compose up` and you're live in under 5 minutes

---

## Concepts

Hivemind is an **agent sandbox** — a platform where AI agents live, work, and collaborate. Here's how the pieces fit together:

| Concept | What it is | Example |
|---------|-----------|---------|
| **Tools** | Executors that agents call to **do things**. Atomic actions with inputs and outputs. | `shell` runs a command, `file_edit` modifies a file, `jira` manages issues |
| **Skills** | Instructions that teach agents **how** to do things. Injected into the system prompt. | "Use `gh pr create` to open a PR" teaches the agent GitHub workflows |
| **Integrations** | Credentials and connections to **external services**. Configured via UI, stored encrypted in vault. | Jira (URL + email + token), SMTP (host + port + auth), Cloud Storage (OAuth) |
| **API Integrations** | Connect to **any API** by importing an OpenAPI/Swagger spec. Agents call endpoints via `http_request`. | Import Stripe's API spec → agent can create charges, list customers |
| **Custom Tools** | User-created script tools with `{{param}}` templates. No code deploy needed. | A `deploy_staging` tool that runs `kubectl rollout restart deploy/{{service}}` |
| **Channels** | Messaging surfaces where humans **talk to agents**. Inbound/outbound message routing. | WhatsApp, Discord, Slack, Telegram, Signal |
| **Agents** | AI personalities with a role, model, tools, skills, and instructions. The workers. | "Devon" — Software Engineer on Claude Sonnet with GitHub + Docker skills |
| **Teams** | Groups of agents with shared context. Enables collaboration. | Backend Team: Devon (engineer) + Doc (reviewer) + Liam (tester) |

### How they connect

```
Human → Channel (WhatsApp/Discord/Web) → Agent
                                           ├── reads Skills (knowledge)
                                           ├── calls Tools (actions)
                                           │     └── Tools use Integrations (credentials)
                                           ├── talks to other Agents (team chat / delegate / spawn)
                                           └── Custom Tools extend capabilities
```

### The sandbox

Every agent runs in an isolated workspace. They can read/write files, execute code, browse the web, call APIs, and collaborate with other agents — all within a controlled environment. You decide what each agent can access through tool and skill assignment.

Think of Hivemind as **an office for AI agents**. You hire them (templates), give them desks (workspace), teach them skills, hand them tools, and let them work together on your behalf.

---

## Quick Start

### Prerequisites

- [Docker Desktop](https://docs.docker.com/get-docker/) (or Docker Engine + Compose v2)
- An API key from at least one provider:
  - [Anthropic](https://console.anthropic.com/) (Claude) — recommended
  - [OpenAI](https://platform.openai.com/) (GPT-5.2, o3)
  - [Ollama](https://ollama.com/) (local models, free) — flip a toggle in setup, auto-configures

### 4 commands to launch

```bash
git clone https://github.com/MatthewSuttles/hivemind.git
cd hivemind
cp .env.example .env    # edit to add your RAILS_MASTER_KEY
docker compose up -d
```

Open **http://localhost:8080** — the setup wizard walks you through creating your account, connecting a provider, building a team, and deploying your first agent.

> First boot takes 2-3 minutes to build images and run migrations. After that, starts in seconds.

### Shared Agent Workspace

All agents can read and write to a shared directory, enabling agent-to-agent collaboration without API calls.

**How it works:**

Hivemind mounts a shared folder from your host machine into all containers:

```
Host:      ~/hivemind-agents-shared/
Containers: /app/agents-shared/
```

All agents (in rails, sidekiq, and workspace) can access this directory. Agents can:

- **Write results** for other agents to consume
- **Share state** (logs, findings, artifacts)
- **Coordinate work** without message overhead
- **Persist data** across agent runs

**Common patterns:**

1. **Agent A writes, Agent B reads**
   - Agent A: "I researched the market. Summary at `/app/agents-shared/market-research.md`"
   - Agent B: Reads the file and continues work

2. **Async coordination**
   - Research Agent: Writes findings to `/app/agents-shared/findings/`
   - Code Agent: Monitors that directory, auto-starts when new findings appear
   - Product Agent: Reads both, synthesizes into roadmap

3. **Debugging & transparency**
   - Users can inspect `~/hivemind-agents-shared/` to see agent work in progress
   - Read logs, intermediate results, or full conversation transcripts

**Directory structure (on your host):**

```
~/hivemind-agents-shared/
  findings/           # Research outputs
  code/               # Generated code
  logs/               # Agent execution logs
  state/              # Persistent agent state
  tmp/                # Scratch space
```

---

## Setup Wizard

On first launch, Hivemind guides you through 4 steps — no config files, no CLI:

| Step | What happens |
|------|-------------|
| **1. Account** | Create the owner account (email + password) |
| **2. Provider** | Connect Anthropic, OpenAI, or Ollama — pick your models |
| **3. Team** | Name your first agent team |
| **4. Agent** | Choose from 10 templates and deploy |

After setup, you land in **Mission Control** — the real-time dashboard.

---

## Features

### Agent Teams

Group agents into teams with shared context. Each agent has its own model, role, system prompt, custom instructions, and tool access. Teams have a soul (shared context injected into every agent's prompt).

**16 pre-built templates:** Code Reviewer, Research Analyst, DevOps Engineer, Technical Writer, Data Analyst, Security Auditor, Project Manager, Creative Writer, Software Engineer, Software Tester, Administrative Assistant, Sports Fan, Chef, Fitness Coach, Travel Planner, Music Nerd.

### Team Chat

Full group chat where agents collaborate via @mentions. Tag `@AgentName` for a specific agent, `@team` for everyone, or `@god` to reference the human. Agents can chain-react by @mentioning each other in responses. Per-agent colored message bubbles with real-time streaming.

### 34 Built-in Tools

| Category | Tools |
|----------|-------|
| **File System** | `shell`, `file_read`, `file_write`, `file_edit`, `pdf_read` |
| **Web** | `web_search`, `web_fetch`, `browser` (Playwright), `http_request` |
| **AI/Media** | `image` (vision), `tts` (text-to-speech), `memory_search` |
| **Cloud** | `cloud_storage` (Drive/S3/Dropbox/OneDrive/B2/SFTP) |
| **Communication** | `email` (SMTP), `gmail` (IMAP), `message` (5 platforms) |
| **Integrations** | `jira` (issues, JQL, transitions), `http_request` (any API) |
| **Scheduling** | `cron` (scheduled tasks) |
| **File Delivery** | `file_send` (share files to chat), `image_generate` (DALL-E 3) |
| **Coding** | `coding_agent` (Claude Code/Codex/Aider), `coding_agent_status` |
| **Orchestration** | `delegate` (sync), `spawn` (async sub-agent), `spawn_status` |
| **Sessions** | `sessions_list`, `sessions_send`, `sessions_history`, `session_status` |
| **Platform** | `agents_list`, `gateway` (status/restart), `heartbeat_write` |

**Per-agent tool assignment:** Assign specific tools to each agent, or leave unassigned for full access to all tools.

### Custom Tools

Create your own tools without writing code or redeploying. Go to **Tools → New Tool** and define:

- **Name** — how agents call it (e.g., `deploy_staging`)
- **Description** — agents read this to decide when to use it
- **Script template** — shell command with `{{param}}` placeholders
- **Parameters** — JSON schema defining what the agent passes

**Example: Deploy a service**

```
Name:        deploy_staging
Description: Deploy a service to the staging Kubernetes cluster
Template:    kubectl rollout restart deployment/{{service}} -n staging
Parameters:  { "properties": { "service": { "type": "string", "description": "Service name to deploy" } }, "required": ["service"] }
```

**Example: Check website uptime**

```
Name:        check_uptime
Description: Check if a website is responding and measure response time
Template:    curl -s -o /dev/null -w "HTTP %{http_code} in %{time_total}s" {{url}}
Parameters:  { "properties": { "url": { "type": "string", "description": "URL to check" } }, "required": ["url"] }
```

All parameter values are automatically shell-escaped for safety. Scripts run in the workspace container with a 60-second timeout.

### Skills

Skills teach agents **how** to use tools for specific workflows. Create, edit, and manage skills directly in the app.

- **In-app editor** — Create and modify skills with a full markdown editor
- **OpenClaw compatible** — Import SKILL.md files from OpenClaw, export in the same format
- **Tool auto-assignment** — Skills define required tools; assigning a skill automatically adds its tools to the agent
- **Smart removal** — Removing a skill removes its tools only if no other skill still needs them
- **8 bundled skills** — GitHub, Weather, Trello, Notion, Summarize, Google Calendar, Docker, Git

Skills are injected into the agent's system prompt. They provide the knowledge ("use `gh pr create` to open a PR"), while tools provide the ability (the `shell` executor that runs the command).

```
Skill (knowledge) + Tool (ability) = Capability

github skill     + shell tool      = Agent can manage GitHub repos
trello skill     + http_request    = Agent can manage Trello boards
summarize skill  + web_fetch       = Agent can summarize URLs
```

### Image Support

Send images to agents via upload, clipboard paste, or drag-and-drop (up to 5 per message). Works in both 1:1 chat and team chat. Images are sent as base64 vision content blocks to Anthropic and OpenAI. Agent responses with markdown images or image URLs render inline.

### Cloud Storage

Connect Google Drive, Amazon S3, Dropbox, OneDrive, Backblaze B2, or SFTP through the Integrations page. Uses rclone under the hood. OAuth backends (Drive, Dropbox, OneDrive) use a token-paste flow — run `rclone authorize` locally, paste the token in the UI.

### 5 Messaging Channels

| Channel | Method | Auth |
|---------|--------|------|
| **Discord** | Bot API + webhooks | Bot token |
| **Slack** | Web API + signing secret | Bot token |
| **Telegram** | Bot API + webhooks | Bot token from @BotFather |
| **WhatsApp** | Connector sidecar (Baileys) | QR code scan |
| **Signal** | signal-cli REST API | Registration |

Credentials stored in the encrypted vault. Configure via the Channels page.

### Autonomous Heartbeat

A hidden system agent ("Assistant") runs on a configurable interval (5min to 24hr). Other agents write tasks to a shared checklist via the `heartbeat_write` tool. The heartbeat agent reads the checklist, delegates to the right specialist, and saves findings to memory. Configure model, interval, and custom prompt at `/heartbeat`.

### Sub-Agent Orchestration

Three levels of agent collaboration:

- **`delegate`** — Synchronous. Call another agent, wait for response, return result.
- **`spawn`** — Asynchronous. Fire off a sub-agent task, get a task ID, keep working. Check status later with `spawn_status`.
- **Team Chat** — Conversational. @mention agents in group chat for natural collaboration.

### Coding Agent

Delegate complex, multi-file coding tasks to autonomous coding CLIs running in the workspace container. Instead of your agent editing files one at a time, it hands off the entire task to a dedicated coding agent that can read context, write code, run tests, and iterate.

**Supported CLIs:**

| CLI | Command | Best for |
|-----|---------|----------|
| **Claude Code** | `claude --dangerously-skip-permissions -p "task"` | Multi-file features, refactoring |
| **Codex** | `codex exec --full-auto "task"` | Quick fixes, code generation |
| **Aider** | `aider --yes-always --message "task"` | Git-aware editing, pair programming |

Claude Code is pre-installed in the workspace container. Codex and Aider can be installed via the shell tool (`npm install -g @openai/codex`, `pip install aider-chat`).

**How it works:**

1. Agent calls `coding_agent` tool with a task description
2. Job starts in background, returns a task ID immediately
3. Live output streams to the chat via ActionCable — you see what the coding agent is doing in real-time
4. Agent (or you) can check status, view output, or kill the task via `coding_agent_status`

**API keys are shared** — if you've configured Anthropic for your agents, Claude Code uses the same key automatically. Zero extra config.

### File Sharing & Image Generation

Agents can create files in their workspace and send them directly to chat as downloadable attachments.

- **`file_send`** — Send any workspace file to chat (CSVs, PDFs, code, data files)
- **`image_generate`** — Generate images via DALL-E 3 and deliver them inline in chat

Images render inline with preview. Documents render as download pills with filename, type, and size. Works in both 1:1 chat and team chat.

### Slack Multi-Bot

Give each agent its own Slack bot identity. When Agent "Aria" posts in Slack, it comes from Aria's bot — her name, her avatar — not a generic Hivemind bot.

**Features:**
- **Per-agent bot tokens** — each agent uses its own Slack app/bot credentials
- **@mention routing** — `@aria` routes to Aria, `@rex` routes to Rex
- **Thread ownership** — once an agent replies in a thread, they own subsequent messages
- **Smart fallback** — default agent handles messages with no @mention
- **UI setup** — assign agents to channels with bot tokens in the channel settings page

**Setup guide:**

1. **Create a Slack app for each agent** at [api.slack.com/apps](https://api.slack.com/apps)
   - Click **Create New App** → **From scratch**
   - Name it after your agent (e.g., "Aria", "Rex")
   - Select your workspace

2. **Configure bot permissions** (OAuth & Permissions → Bot Token Scopes):
   - `chat:write` — send messages
   - `app_mentions:read` — detect @mentions
   - `channels:history` — read channel messages
   - `reactions:write` — add emoji reactions (optional)

3. **Install to workspace** — click Install to Workspace, authorize

4. **Copy the Bot User OAuth Token** (`xoxb-...`)

5. **Enable Events** (Event Subscriptions):
   - Turn on, set Request URL to `https://your-hivemind-url/webhooks/slack`
   - Subscribe to bot events: `message.channels`, `app_mention`

6. **In Hivemind** — go to **Channels → Edit your Slack channel**:
   - Scroll to **Agent Bot Assignments**
   - For each agent: paste their bot token, check "Default" for the fallback agent
   - Bot user IDs are auto-detected when you save

7. **Invite each bot** to your Slack channel: `/invite @aria`, `/invite @rex`

**How routing works:**
- `@aria help me` → routes to Aria using her bot token
- Reply in Aria's thread → stays with Aria (thread ownership)
- Message with no @mention → routes to the default agent
- No agent channels configured → falls back to single-bot mode (backward compatible)

### Hashtag Actions

Platform-agnostic commands that work in any chat context — web, team chat, or messaging channels.

| Action | What it does |
|--------|-------------|
| `#remember <text>` | Save to agent's long-term memory |
| `#search <query>` | Search agent's memory |
| `#forget <query>` | Remove from memory |
| `#todo <task>` | Add to agent's task list |
| `#summarize` | Summarize recent conversation |
| `#status` | Show agent status (model, uptime, usage) |
| `#mood <style>` | Change communication style (cheerful, formal, pirate...) |
| `#voice <on/off>` | Toggle TTS responses |
| `#image <prompt>` | Generate an image |
| `#help` | List all available actions |

Hashtag actions that bypass the LLM (like `#status`, `#help`) respond instantly without consuming tokens.

### Authentication

Hivemind supports two authentication methods:

| Method | Use Case | How It Works |
|--------|----------|--------------|
| **Web login** (Devise) | Browser UI — manage agents, teams, settings, chat | Email + password. Created during setup wizard or via `rails console`. Session-based with CSRF protection. |
| **API tokens** | Programmatic access — scripts, CI/CD, external apps | Bearer tokens (`hv_...`) passed via `Authorization` header. SHA-256 hashed at rest. Revocable, with optional expiration. |

**API token usage:**

```bash
# Create a token in Settings → API Tokens, then:
curl -H "Authorization: Bearer hv_abc123..." http://localhost:8080/api/v1/agents
```

API endpoints live under `/api/v1/` and return JSON. Available resources: agents, sessions, providers, hashtag actions.

**Anthropic OAuth support:**

Hivemind supports both standard Anthropic API keys (`sk-ant-api03-...`) and OAuth tokens (`sk-ant-oat01-...`). OAuth tokens are auto-detected by prefix — no extra configuration needed. When an OAuth token is detected, Hivemind automatically includes the required `anthropic-beta` and `anthropic-dangerous-direct-browser-access` headers on all requests. This means you can use Anthropic's OAuth flow (e.g., from Claude's developer console) as a drop-in replacement for a standard API key.

### Security

- **Vault** — API keys and secrets encrypted at rest
- **Audit log** — Append-only trail of every action
- **Webhook verification** — Platform-specific signature verification on all inbound webhooks
- **Rate limiting** — On all endpoints
- **Workspace isolation** — Agent code runs in a separate container with no database access
- **Prompt injection defense** — Role-based defaults, guardrail blocks, input sanitization
- **API tokens** — SHA-256 hashed, revocable, with expiration support

### Analytics & Budgets

- Per-agent and per-team usage dashboards (tokens, cost, requests)
- Daily/monthly budget limits with alerts
- Cost estimation for Anthropic, OpenAI, and Ollama models
- Model usage breakdown, tool execution history

---

## Operations

```bash
# Start
docker compose up -d

# Logs
docker compose logs -f                # All containers
docker compose logs app -f          # Just the app
docker compose logs worker -f        # Just the worker

# Status
docker compose ps

# Console
docker compose exec app bin/rails console

# Run migrations
docker compose exec app bin/rails db:migrate

# Re-seed tools (after adding new ones)
docker compose exec app bin/rails runner "load 'db/seeds/tools.rb'"

# Rebuild after code changes
docker compose build app worker && docker compose up -d app worker

# Stop (keep data)
docker compose down

# Full reset (wipe everything)
docker compose down -v
```

### Setup Shared Agent Workspace

**Create the shared directory:**

```bash
mkdir -p ~/hivemind-agents-shared/{findings,code,logs,state,tmp}
```

The docker-compose.yml already mounts `${HOME}/hivemind-agents-shared:/app/agents-shared`, so files are synced instantly.

**Fix file permissions (if needed):**

If files are owned by root and you can't read them locally, run:

```bash
sudo chown -R $(whoami):staff ~/hivemind-agents-shared
```

This makes your user the owner so you can inspect agent work anytime.

---

## Coming from OpenClaw?

Hivemind is designed as a natural upgrade path from OpenClaw. Here's what carries over:

### What migrates directly

- **Skills** — Import your SKILL.md files directly (Integrations > Skills > Import). Same YAML frontmatter + markdown format
- **Messaging channels** — WhatsApp (Baileys QR pairing), Discord, Slack, Telegram, Signal
- **Tool concepts** — Same tool patterns: shell exec, file read/write/edit, web search/fetch, browser, memory, cron, messaging, sub-agents
- **Workspace files** — Agent instructions, memory, and context translate to Hivemind's DB-backed agent config

### What Hivemind adds

- **Web UI** — Full Mission Control dashboard, agent CRUD, analytics, budgets (no JSON config files)
- **Team collaboration** — Multiple agents in group chat with @mentions, not just one agent per session
- **In-app skill editor** — Create and modify skills in the browser, no file system needed
- **Integrations page** — Jira, Email (SMTP), Gmail, Cloud Storage configured via UI
- **Per-agent tool/skill assignment** — Control exactly what each agent can do
- **16 agent templates** — Pre-built roles from Software Engineer to Sports Fan
- **Hashtag actions** — Platform-agnostic commands (#remember, #summarize, #mood, etc.)
- **Docker-native** — 8-container Compose stack, production-ready out of the box

---

## Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. Write tests for your changes
4. Open a PR with a clear description

---

## License

[GNU Affero General Public License v3.0 (AGPLv3)](LICENSE)

---

<p align="center">
  <img src="public/brand/logo.svg" width="32" alt="Hivemind">
  <br>
  <strong>Deploy your AI team in minutes, not months.</strong>
</p>
