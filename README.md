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
  <a href="https://github.com/hivementality-ai/hivemind/actions/workflows/ci.yml"><img src="https://github.com/hivementality-ai/hivemind/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <a href="https://codecov.io/gh/hivementality-ai/hivemind"><img src="https://codecov.io/gh/hivementality-ai/hivemind/branch/main/graph/badge.svg" alt="Coverage"></a>
  <a href="https://discord.gg/Cww4rFz7"><img src="https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=flat&logo=discord&logoColor=white" alt="Discord"></a>
  <img src="https://img.shields.io/badge/Docker-Compose-2496ED?style=flat&logo=docker" alt="Docker">
  <img src="https://img.shields.io/badge/License-AGPLv3-blue?style=flat" alt="License">
</p>

---

## Table of Contents

- [Why Hivemind?](#why-hivemind)
- [System Requirements](#system-requirements)
- [Concepts](#concepts)
- [Quick Start](#quick-start)
- [Setup Wizard](#setup-wizard)
- [Features](#features)
  - [Agent Teams](#agent-teams)
  - [Team Chat](#team-chat)
  - [34 Built-in Tools](#34-built-in-tools)
  - [Custom Tools](#custom-tools)
  - [Skills](#skills)
  - [Web Search](#web-search)
  - [Image Support](#image-support)
  - [Cloud Storage](#cloud-storage)
  - [5 Messaging Channels](#5-messaging-channels)
  - [Autonomous Heartbeat](#autonomous-heartbeat)
  - [Sub-Agent Orchestration](#sub-agent-orchestration)
  - [Coding Agent](#coding-agent)
  - [File Sharing & Image Generation](#file-sharing--image-generation)
  - [Slack Multi-Bot](#slack-multi-bot)
  - [Hashtag Actions](#hashtag-actions)
  - [Authentication](#authentication)
  - [Security](#security)
  - [Analytics & Budgets](#analytics--budgets)
- [Operations](#operations)
- [Best Practices](#best-practices)
- [Coming from OpenClaw?](#coming-from-openclaw)
- [Contributing](#contributing)
- [License](#license)

---

## Why Hivemind?

Most AI platforms give you one agent in a chat box. Hivemind gives you a **team**.

- **Multiple specialized agents** with different models, roles, and tools
- **Team chat** with @mentions — agents collaborate and chain-react
- **34 built-in tools** — shell, files, browser, Jira, email, cloud storage, Gmail, vision, TTS, and more
- **Skills system** — teach agents new capabilities, import OpenClaw SKILL.md files
- **5 messaging channels** — Discord, Slack, Telegram (coming soon), WhatsApp, Signal (coming soon)
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

## Why We're Here

The AI industry is obsessed with building one agent that can "do it all." We think that's fundamentally wrong.

**Specialized agents outperform generalists every time.** A focused code reviewer catches more bugs than a general assistant. A dedicated research agent finds better sources than a multipurpose chatbot. When you optimize for one domain instead of trying to cover everything, you get better accuracy, lower latency, and systems that are actually debuggable and maintainable.

**The future is composition, not consolidation.** Complex workflows emerge from simple, reliable components working together—not from increasingly complex monoliths. Each agent in your team becomes highly reliable at what it does. You get clear separation of concerns, the ability to swap agents without breaking everything, and better resource utilization because you're not running frontier models for simple tasks.

**But specialization is just the starting point—agents get smarter over time.** Hivemind agents don't just start optimized for their domain; they continuously improve through memory systems that retain past interactions, context, and learnings. With our mini-RAG system (coming soon), agents build an ever-growing knowledge base from accumulated experience, creating a learning curve advantage that compounds with each interaction.

**And here's the key: your agents aren't locked to a single model.** Mix and match specialized agents from any provider—Anthropic's Claude for reasoning, OpenAI's GPT for creativity, local Ollama models for lightweight tasks. They collaborate as a cohesive system despite their diversity, giving you the best tool for each job instead of forcing everything through one model's constraints.

**Hivemind embodies this philosophy.** We're not building another "ChatGPT for everything." We're building a platform where specialized AI agents can work as a team. Quality over breadth. Collaboration over consolidation. That's why we're here.

---

## System Requirements

You need [Docker and Docker Compose](https://docs.docker.com/get-docker/) to run Hivemind.

**Hardware:**
- 2+ CPU cores
- 2GB+ RAM  
- 5GB+ disk space

That's it. Everything else runs in containers.

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
| **Channels** | Messaging surfaces where humans **talk to agents**. Inbound/outbound message routing. | WhatsApp, Discord, Slack, Telegram (coming soon), Signal (coming soon) |
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

## What Can I Do with Hivemind?

Here are some real examples to spark ideas:

| # | Use Case | How It Works |
|---|----------|-------------|
| 🛠️ | **Build a dev team that ships code while you sleep** | Create specialized agents — one writes code, one reviews PRs, one runs tests. Assign them GitHub + Docker + shell tools, put them on a team, and point them at your backlog. They collaborate via team chat and open PRs for your approval. |
| 📧 | **Manage and send emails on your behalf** | Connect SMTP + IMAP integrations, give an agent the email skill, and let it draft replies, triage your inbox, or send outreach. It reads context from past conversations so responses stay on-brand. |
| 💬 | **Run multiple specialized bots in Slack or Discord** | Each agent gets its own bot identity in your workspace. A support bot answers customer questions, a deploy bot handles releases, and a standup bot collects daily updates — all managed from one Hivemind instance. |
| 📊 | **Monitor infrastructure and alert you** | Give an agent shell + Docker tools with a cron schedule. It checks container health, disk usage, and API uptime every 15 minutes. When something breaks, it messages you on WhatsApp or Discord with the diagnosis. |
| 🔍 | **Research anything and deliver a report** | An agent with web browsing, web search, and file tools can deep-dive into competitors, market trends, or technical topics. It writes structured reports and saves them to your workspace. |
| 🎫 | **Automate Jira ticket → PR workflows** | Import your Jira integration, teach an agent your codebase conventions via skills, and point it at tickets. It reads the ticket, writes a plan, generates code with tests, and opens a draft PR — all hands-free. |
| 🔌 | **Connect to any API without writing code** | Import an OpenAPI/Swagger spec (Stripe, Twilio, HubSpot, your internal APIs) and agents can call those endpoints immediately. No custom tool code needed. |
| 📝 | **Generate and publish content on a schedule** | A writing agent with web search + a cron job can research topics, write blog posts, and open PRs to your site repo on a biweekly cadence. You just review and merge. |
| 🏗️ | **Delegate one-off tasks to disposable agents** | Spawn a sub-agent for a specific job — "migrate this CSV to the new schema" or "audit these 50 dependencies for vulnerabilities." It runs in isolation, reports back, and cleans up. |
| 🧠 | **Build agents that learn and improve over time** | Hivemind's memory system stores interactions, extracts facts, and builds semantic knowledge. Your agents remember past decisions, user preferences, and lessons learned — getting better the more they work. |

> **The pattern:** Pick a role → assign the right tools and skills → connect a channel → let it work. Hivemind handles orchestration, memory, credentials, and collaboration.

---

## Quick Start

### One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/hivementality-ai/hivemind/main/install.sh | bash
```

That's it. The installer handles Docker, cloning, secrets, and startup. Open **http://localhost:8080** when it's done.

> **What it does:** checks for Docker (installs if missing), clones the repo, generates encryption keys and `.env`, builds containers, and starts everything.

### Or install manually

<details>
<summary>Click to expand manual setup</summary>

**Prerequisites:**
- [Docker Desktop](https://docs.docker.com/get-docker/) (or Docker Engine + Compose v2)
- An API key from at least one provider:
  - [Anthropic](https://console.anthropic.com/) (Claude) — recommended. **Pro/Max subscribers can use their existing subscription instead of API billing** (just paste your OAuth token)
  - [OpenAI](https://platform.openai.com/) (GPT-5.2, o3)
  - [Ollama](https://ollama.com/) (local models, free) — flip a toggle in setup, auto-configures

```bash
git clone https://github.com/hivementality-ai/hivemind.git
cd hivemind
./install.sh
```

</details>

The setup wizard walks you through creating your account, connecting a provider, building a team, and deploying your first agent.

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
| **Scheduling** | `cron` (prompt-based scheduled agent turns), `cron_script` (script-based scheduled tasks) |
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

### Web Search

The `web_search` tool supports configurable search providers. Configure your preferred provider in **Settings → Integrations → Web Search**.

| Provider | Free Tier | Results |
|----------|-----------|---------|
| **Brave Search** | 2,000 queries/mo | Brave index |
| **SearchAPI.io** | 100 queries/mo | Google results |
| **SerpAPI** | 100 queries/mo | Google results |
| **DuckDuckGo** | Unlimited (default) | Instant answers only |

DuckDuckGo works out of the box with no API key but only returns instant answers (Wikipedia-style). For real search results, configure one of the other providers.

Agents can pass optional parameters: `count` (number of results), `country` (2-letter code), and `language` (ISO code).

### Image Support

Send images to agents via upload, clipboard paste, or drag-and-drop (up to 5 per message). Works in both 1:1 chat and team chat. Images are sent as base64 vision content blocks to Anthropic and OpenAI. Agent responses with markdown images or image URLs render inline.

### Cloud Storage

Connect Google Drive, Amazon S3, Dropbox, OneDrive, Backblaze B2, or SFTP through the Integrations page. Uses rclone under the hood. OAuth backends (Drive, Dropbox, OneDrive) use a token-paste flow — run `rclone authorize` locally, paste the token in the UI.

### 5 Messaging Channels

| Channel | Method | Auth |
|---------|--------|------|
| **Discord** | Bot API + webhooks | Bot token |
| **Slack** | Web API + signing secret | Bot token |
| **Telegram** (coming soon) | Bot API + webhooks | Bot token from @BotFather |
| **WhatsApp** | Connector sidecar (Baileys) | QR code scan |
| **Signal** (coming soon) | signal-cli REST API | Registration |

Credentials stored in the encrypted vault. Configure via the Channels page.

### Autonomous Heartbeat

A hidden system agent ("Assistant") runs on a configurable interval (5min to 24hr). Other agents write tasks to a shared checklist via the `heartbeat_write` tool. The heartbeat agent reads the checklist, delegates to the right specialist, and saves findings to memory. Configure model, interval, and custom prompt at `/heartbeat`.

### Sub-Agent Orchestration

Three levels of agent collaboration:

- **`delegate`** — Synchronous. Call another agent, wait for response, return result.
- **`spawn`** — Asynchronous with callback. Fire off a sub-agent task — when it completes, the result is automatically injected back into the parent agent's session. The parent agent wakes up, processes the result, and can take further action. All server-side, works whether the user is watching or not. Recursion guard at 3 levels deep.
- **Team Chat** — Conversational. @mention agents in group chat for natural collaboration.

### Agent Interrupt

Users can interrupt agents mid-execution — no more waiting for a long tool loop to finish:

- **Cancel (■ button)** — Stops the agent immediately. Partial output saved to transcript.
- **Redirect (send message while agent is working)** — Stops current work, starts on the new message.
- **Inject (API)** — Adds context to the conversation mid-tool-loop without stopping the agent.

Signals are Redis-backed with a 60-second TTL. The tool loop checks for signals before each LLM call and tool execution.

### Scheduled Tasks

Two types of scheduled tasks:

- **`cron`** — Prompt-based. Agent wakes up in a fresh session with full tool access and follows the prompt instructions. Two-stage confirmation flow for safety.
- **`cron_script`** — Script-based. Runs a script (`.py`, `.rb`, `.sh`) in the workspace container on schedule. Output and exit code captured to a session for logging.

Use prompt-based cron when the agent needs to think and use tools. Use script cron for deterministic, repeatable tasks.

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

### Agent Memory

Agents remember conversations and can recall past interactions using `#remember`, `#search`, and `#forget`. Memory is stored per-agent in PostgreSQL.

For **semantic memory** (meaning-based recall, not just keyword matching), Hivemind needs an embedding model to generate vector representations of memories. The install script will offer to set this up for you using [Ollama](https://ollama.com) + `nomic-embed-text` — a lightweight, free, fully local model (~274MB, ~500MB RAM). No API keys or external services required.

If you prefer, you can use OpenAI's embedding API instead — add your API key under **Settings → Integrations**.

Without an embedding model, agents still save and recall memories using keyword search. Semantic search is optional but recommended.

| Config | Default | Description |
|--------|---------|-------------|
| `MEMORY_EMBEDDINGS_ENABLED` | `true` | Enable/disable embedding generation |
| `MEMORY_EMBEDDINGS_PROVIDER` | `ollama` | `ollama` or `openai` |
| `OLLAMA_BASE_URL` | `http://host.docker.internal:11434` | Ollama API endpoint |

### Authentication

Hivemind supports two authentication methods:

| Method | Use Case | How It Works |
|--------|----------|--------------|
| **Web login** | Browser UI — manage agents, teams, settings, chat | Email + password. Created during setup wizard. Session-based with CSRF protection. |
| **API tokens** | Programmatic access — scripts, CI/CD, external apps | Bearer tokens (`hv_...`) passed via `Authorization` header. SHA-256 hashed at rest. Revocable, with optional expiration. |

**API token usage:**

```bash
# Create a token in Settings → API Tokens, then:
curl -H "Authorization: Bearer hv_abc123..." http://localhost:8080/api/v1/agents
```

API endpoints live under `/api/v1/` and return JSON. Available resources: agents, sessions, providers, hashtag actions.

**Use your Anthropic Pro or Max subscription (no API billing needed):**

If you have an Anthropic Pro ($20/mo) or Max ($100/mo) subscription, you can use it directly with Hivemind instead of paying separately for API tokens. Just paste your OAuth token in the provider setup — no API billing, no usage-based charges.

1. Go to [console.anthropic.com](https://console.anthropic.com/) and sign in with your Pro/Max account
2. Generate an OAuth token (`sk-ant-oat01-...`)
3. Paste it as your Anthropic API key in Hivemind's provider settings

Hivemind auto-detects OAuth tokens by prefix and adds the required headers automatically. Everything just works — same models, same quality, powered by your existing subscription.

Standard API keys (`sk-ant-api03-...`) also work if you prefer usage-based billing.

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
docker compose logs app -f            # Just the app
docker compose logs worker -f         # Just the worker

# Status
docker compose ps

# Database setup (first time only)
docker compose exec app bin/setup

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

## Best Practices

### Use local models when possible

Run [Ollama](https://ollama.com) alongside Hivemind and assign local models to agents that don't need frontier-level reasoning. Great for:

- **Triage agents** — Route messages, classify intent, tag tickets
- **Summarizers** — Condense logs, threads, or documents
- **Heartbeat/cron tasks** — Periodic checks that don't need deep reasoning
- **Draft generators** — First-pass content that gets reviewed by a stronger model

Reserve cloud models (Claude, GPT) for complex reasoning, code generation, and production-critical work. This keeps costs low and latency predictable.

### Right-size your models

Not every agent needs the most powerful model. Match the model to the job:

| Task | Recommended |
|------|-------------|
| Chat routing, classification | Local (llama3, mistral) |
| Summarization, formatting | Local or Haiku |
| Code review, debugging | Sonnet or GPT-4o |
| Architecture, complex reasoning | Opus or o1 |

You can set different models per agent in the agent settings page.

### Set budgets early

Configure daily and monthly spend limits per agent in **Analytics & Budgets** before giving agents expensive tools. It's easier to raise a limit than to explain an unexpected bill.

### Scope your tools

Don't give every agent access to every tool. A research agent doesn't need `shell`. A code reviewer doesn't need `email`. Use per-agent tool assignment to enforce least-privilege.

### Use teams with clear roles

Agents work better when they have focused roles. Instead of one "do everything" agent:

- Create specialized agents (researcher, coder, reviewer, writer)
- Group them into a team with a shared soul (team context)
- Use @mentions in team chat to orchestrate handoffs

### Invest in your agents upfront

The more context, memory, and skills you give an agent early on, the better it performs over time — and the less it costs per interaction.

**How Hivemind keeps costs low automatically:**

- **Prompt caching** — System prompts are split into cacheable blocks. After the first message, Anthropic caches the static prefix and subsequent calls pay ~10% of the original cost for those blocks.
- **Skill-on-demand** — Skills aren't injected into every API call. Agents see a one-line summary of each skill and load full instructions via tool call only when needed. A "hello" costs zero skill tokens.
- **Conversation summarization** — Older messages are compressed into a rolling ~200-token summary instead of sending raw transcript. A 50-message conversation doesn't mean 50 messages in the API call.
- **Memory filtering** — Greetings and small talk are filtered out of memory retrieval. Only meaningful context gets injected.

**What this means in practice:**

| Scenario | Input tokens |
|----------|-------------|
| Agent with 4 skills says hello | ~400 tokens |
| Same agent after prompt cache hit | ~200 tokens |
| Agent loads a skill for a coding task | +500 tokens (one-time) |
| Long conversation (50+ messages) | Capped by summarization |

**The investment that pays off:**

- Write detailed skill instructions — they're loaded on-demand, so length doesn't hurt casual usage
- Give agents rich system prompts — the static parts are cached after the first call
- Let agents build memories — good memory context means fewer clarification rounds
- Use team souls for shared context — written once, cached across all team members

The pattern: **front-load quality context, and the system handles efficiency automatically.**

### Keep system prompts focused

System prompts are cached, so length isn't as costly as it used to be — but focused prompts still produce better agent behavior. Put stable shared context in the team soul and keep individual agent prompts about their specific role, personality, and expertise.

### Use the workspace for state

Agents can read/write files in the shared workspace (`~/hivemind-agents-shared/`). Use it for:

- Persistent memory across sessions
- Shared findings between agents
- Logs and audit trails
- Intermediate work products

Files survive restarts. Agent memory doesn't (unless you persist it).

### Monitor before you scale

Start with 2-3 agents. Watch their behavior in team chat. Check analytics for token usage and error rates. Add agents once the workflow is proven.

---

## Coming from OpenClaw?

Hivemind is designed as a natural upgrade path from OpenClaw. Here's what carries over:

### What migrates directly

- **Skills** — Import your SKILL.md files directly (Integrations > Skills > Import). Same YAML frontmatter + markdown format
- **Messaging channels** — WhatsApp (Baileys QR pairing), Discord, Slack, Telegram (coming soon), Signal (coming soon)
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
