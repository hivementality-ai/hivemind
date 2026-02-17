# Releases

Hivemind uses **CalVer** (`YYYY.MM.PATCH`) for versioning. [Learn more about our versioning strategy.](docs/upgrading.md)

---

## 2026.02.1 — February 17, 2026

**Initial Release** 🐝

### Features
- **Agent Runtime** — Multi-agent platform with 34 built-in tools
- **Team Chat** — Group chat with @mentions, agents collaborate and chain-react
- **16 Agent Templates** — Pre-built roles from Software Engineer to Music Nerd
- **8 Bundled Skills** — GitHub, Weather, Trello, Notion, Summarize, Google Calendar, Docker, Git
- **5 Messaging Channels** — Discord, Slack, Telegram, WhatsApp, Signal
- **Slack Multi-Bot** — Each agent gets its own Slack bot identity with thread routing
- **Coding Agent** — Delegate to Claude Code, Codex, or Aider with live progress streaming
- **Sub-Agent Orchestration** — delegate (sync), spawn (async), team chat
- **Extended Thinking** — Anthropic thinking/reasoning support with per-agent toggle and budget
- **Anthropic OAuth** — Auto-detect `sk-ant-oat01-*` tokens, no extra config needed
- **Image Support** — Send/receive images via upload, paste, drag-and-drop (up to 5 per message)
- **File Sharing** — Agents create files and deliver them as downloadable attachments
- **Cloud Storage** — Google Drive, S3, Dropbox, OneDrive, B2, SFTP via rclone
- **Custom Tools** — Create tools in the UI with shell script templates
- **API Integrations** — Import OpenAPI/Swagger specs, agents call any API
- **Hashtag Actions** — Platform-agnostic commands (#remember, #summarize, #mood, etc.)
- **Autonomous Heartbeat** — Hidden system agent runs periodic checks on configurable interval
- **Analytics & Budgets** — Per-agent token tracking, cost estimation, budget enforcement
- **Security** — Vault-encrypted secrets, audit logging, webhook verification, workspace isolation
- **Markdown Chat** — Agent responses render with full markdown (bold, code blocks, lists, tables)
- **Setup Wizard** — 4-step onboarding: account, provider, team, agent
- **Docker Compose** — 8-container stack: rails, sidekiq, postgres, redis, workspace, browser, connector, docker-proxy
- **One-Line Install** — `curl -fsSL https://hivementality.ai/install.sh | bash`

### Infrastructure
- Rails 8, Ruby 3.4.8
- PostgreSQL with pgvector
- Redis + Sidekiq
- ActionCable for real-time streaming
- Playwright for browser automation

### Notes
- First public release
- CalVer versioning: `YYYY.MM.PATCH`
- Version API: `GET /api/v1/system/version`
