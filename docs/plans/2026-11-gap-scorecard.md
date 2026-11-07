# Hivemind gap scorecard: vs the open-source field

Written 2026-11-07. Read-only research. Competitor facts come from the pages linked below; star counts are as the pages showed them today. Anything I could not source is dropped or marked "not checked".

## Verdict

Hivemind is already wider than most of the field for one person: 76 tool executors, a research loop, memory, cron, projects with approvals, a mobile PWA, 13 messaging channels, and a Claude subscription route plus Ollama. It loses on three things that matter to a non-technical researcher.

1. Trust in answers. The research loop collects sources and writes a report, but nothing checks that a quoted line is really in the source. This is open ground. Whoever ships a quote check first beats the whole field.
2. Install and daily feel. Hivemind is a Docker stack with a setup wizard. Goose, Open WebUI and AnythingLLM ship desktop apps. The gap here is large.
3. Too much surface. Teams, swarms, 13 channels, Jira, Trello and two Gmail tools are noise for one person doing research and projects.

Correction to the brief: Hivemind's "own connectors" are two different things. The `connector/` folder is only a messaging sidecar (WhatsApp, Signal, Slack, Telegram). Data access is a set of single-purpose tool executors (Gmail, Calendar, Drive, Jira, Trello, cloud storage), plus an MCP client and an OpenAPI-spec importer (`ApiIntegration`). There is no catalog layer like Pipedream's, so every new app is either hand code or MCP.

## What Hivemind really has (from code)

- Tools: 76 executor files in app/services/tools. Shell, files, grep/glob, browser (Playwright sidecar), web search and fetch (Brave, DuckDuckGo, SearchAPI, SerpAPI resolvers), PDF read, image read and generate, STT and TTS, cloud storage, Gmail x2, SMTP email, Google Calendar and Drive, Jira, Trello, HTTP request with API integrations, MCP client, canvas, vault, cron and cron_script, delegate and spawn sub-agents, coding agent (Claude Code, Codex, Aider), user model, skill and tool creation.
- Research: `Research::Loop` with quick, standard and deep depths (5/12/25 searches), plan, search, analyze, iterate, synthesize. Runs as a background job with progress and a cancel check. Sources are kept as URLs and per-finding confidence. Has a UI at research_sessions.
- Memory: LLM fact extraction, consolidation job, embeddings via Ollama, keyword fallback, `#remember` and `#forget`. Knowledge base with document ingestion and chunk search.
- Work management: projects with milestones, approve/reject/skip, stall detector, deadline checker, digests. Scheduled tasks, heartbeat. Approval requests with a 24 hour expiry.
- Models: Anthropic (OAuth subscription route through an SDK proxy), OpenAI, Gemini, Ollama, OpenAI-compatible, failover adapter and circuit breaker. `ModelRouter` auto-routes cheap, mid and top tiers, but only for Anthropic and OpenAI; Ollama keeps its pinned model.
- Safety: vault, audit log, network egress control, skill security scanner, container sandbox.
- Surfaces: web UI, mobile PWA with push, 13 channels, desktop pairing.

## Gap table

Gap size is how far Hivemind sits behind the best option for this user (S small, M medium, L large). Port effort is the cost to get it into Hivemind (S under a day of builder time, M a few days, L a week or more). "None found" means none of the pages I read describes it.

| Feature | Hivemind | Best OSS competitor | Gap | Port |
|---|---|---|---|---|
| Deep research with citations | Loop with 3 depths, URL sources, no quote check | [GPT Researcher](https://github.com/assafelovic/gpt-researcher): 20+ sources, citations, PDF/Word/Markdown export, local docs | M | M |
| Report export (PDF, Word, Markdown) | Session export; format not checked | [GPT Researcher](https://github.com/assafelovic/gpt-researcher) | S | S |
| Your own documents with citations | Knowledge base, chunk search with match percent | [AnythingLLM](https://github.com/Mintplex-Labs/anything-llm): drag-and-drop uploads with source citations | S | S |
| Memory you can see and fix | Fact extraction, consolidation, no user-facing contradiction handling found | [Hermes Agent](https://github.com/NousResearch/hermes-agent): persistent memory, search across past conversations; [Open WebUI](https://docs.openwebui.com/features/) memory | M | M |
| Scheduled and watching work | Cron prompt and script, heartbeat | [Khoj](https://github.com/khoj-ai/khoj) scheduled automations and newsletters; [Open WebUI](https://docs.openwebui.com/features/) automations; [Hermes](https://github.com/NousResearch/hermes-agent) natural-language cron | S | S for condition gate, M for quiet hours and digest |
| Reusable workflows / skills | Skills, 150+ templates, swarm export, self-written skills with approval | [Goose recipes](https://goose-docs.ai/docs/guides/recipes/): extensions, prompts and settings packaged | M | M |
| Approval cards before risky actions | ApprovalRequest, project milestone approvals | None found | M | M |
| Published living pages | Live Canvas inside a chat only | [LibreChat artifacts](https://github.com/danny-avila/LibreChat) (React, HTML, Mermaid in chat) | L | L (lite version: S, save canvas as a local page) |
| Meeting and audio notes | STT tool for voice notes | None found in the pages read | L | L for live capture, M for "drop an audio file" |
| Auto model choice | Router for Anthropic and OpenAI only | [AnythingLLM](https://github.com/Mintplex-Labs/anything-llm): dynamic model routing by rules | S | S |
| Connector breadth | Gmail x2, Calendar, Drive, Jira, Trello, MCP, OpenAPI import | [Goose](https://github.com/block/goose): 70+ extensions over MCP | M | M for build-a-connector, S for MCP catalog |
| Proactive "I noticed" | Heartbeat | [Khoj](https://github.com/khoj-ai/khoj) smart notifications | S | M |
| Self-improving skills | Proposal pipeline with approval | [Hermes](https://github.com/NousResearch/hermes-agent): creates and improves skills after hard tasks | S | skip |
| To-dos and reminders | Task manager, projects | None found | S | S |
| Voice (talk to it) | STT and TTS tools | [Open WebUI](https://docs.openwebui.com/features/): hands-free calling | S | M |
| Install and desktop app | Docker compose, installer script, PWA | [Goose](https://github.com/block/goose) native desktop app; [AnythingLLM](https://github.com/Mintplex-Labs/anything-llm) built-in local engine | L | M to L |
| Channels | 13, with per-agent identity | [OpenClaw](https://github.com/openclaw/openclaw): Discord, iMessage, Slack, Teams, Telegram, WhatsApp and 20+ more, plus native apps | Hivemind close | none |
| Coding agent | Claude Code, Codex, Aider delegation | [OpenHands](https://github.com/All-Hands-AI/OpenHands) (agent backends, automations) | none for this user | skip |
| Error mining / self-check | Audit log, `hivemind doctor` | None found | low value | S for a plain weekly health note |

## Competitor headline features (sourced)

- OpenHands ([source](https://github.com/All-Hands-AI/OpenHands)): self-host anywhere; switch between local, remote and cloud agent backends; automations linking Slack, GitHub and Linear by schedule or webhook; any model. MIT.
- Goose ([source](https://github.com/block/goose)): native desktop app, CLI and API; 15+ providers; 70+ MCP extensions; describes itself as general purpose, for "research, writing, automation, data analysis". Apache 2.0. Recipes and subrecipes ([docs](https://goose-docs.ai/docs/guides/recipes/)).
- Open WebUI ([README](https://github.com/open-webui/open-webui), [features](https://docs.openwebui.com/features/)): Ollama and OpenAI-compatible, offline-first; knowledge with hybrid search; web search with cited sources; memory; notes; channels; voice and hands-free calling; code execution; scheduled automations. Its license is its own branded license, not OSI open source.
- AnythingLLM ([source](https://github.com/Mintplex-Labs/anything-llm)): built-in local engine; dynamic model routing; no-code agent builder; document ingestion with source citations; MCP; automatic and user-managed memory. MIT.
- LibreChat ([source](https://github.com/danny-avila/LibreChat)): no-code agents with MCP, skills and subagents; sandboxed code interpreter; artifacts; web search; resumable streams. MIT.
- OpenClaw ([source](https://github.com/openclaw/openclaw)): 20+ channels, native apps on five platforms, state and memory on your hardware, tools/skills/plugins, ClawHub marketplace. MIT. Hivemind already imports from it.
- Others worth watching: Khoj ([source](https://github.com/khoj-ai/khoj), AGPL-3.0, deep research, scheduled automations, Obsidian and WhatsApp), GPT Researcher ([source](https://github.com/assafelovic/gpt-researcher), Apache-2.0), Hermes Agent ([source](https://github.com/NousResearch/hermes-agent), MIT, learning loop, cron, subagents), Dify ([source](https://github.com/langgenius/dify), visual workflows and RAG, modified Apache license).

Closest rivals for this exact user are Khoj (personal, research, AGPL) and GPT Researcher (reports). Neither README I read mentions a quote check or an approval step.

## Build next: top 10 for a non-technical researcher

1. **Quote-checked research.** After the synthesis step, every quoted line must appear in a stored copy of its source page, or it is marked unverified. Store the fetched text per research session (the loop already truncates and holds it). Deterministic string match, no extra model call. This is the one feature no one in the field shows in the pages read. Effort M.
2. **Research library with page-level citations.** Watch a folder, ingest PDFs and notes, cite file and page in every answer. Closes the AnythingLLM gap. Effort S to M, most of it exists in `KnowledgeDocument`.
3. **Watches.** "Tell me when something new shows up on X." Add a cheap pre-check so a check that finds nothing spends no model tokens, plus a quiet-hours window and a morning digest to email or iMessage. Effort S to M.
4. **Router that spans Claude and the Studio.** Extend `ModelRouter` to treat Ollama as the cheap tier: local for summaries and triage, Claude for synthesis. Today Ollama is excluded from auto mode. Effort S.
5. **"What I know about you" page.** Show memories, let her edit and forget, flag contradictions. Effort M.
6. **Approval cards in the app and PWA.** Anything that sends, spends or deletes shows a card with edit-before-approve. Reuse `ApprovalRequest`; add an edit step. Effort M.
7. **One-click Mac install.** A menu bar app or launchd wrapper, a health light, and `hivemind update` already exists. Beats the Docker wizard for her. Effort M to L.
8. **Reports as saved pages.** Every finished research run becomes a page she can reopen, with PDF, Word and Markdown download. No hosting. Effort M.
9. **Audio file to notes.** Drop a recording, get notes and action items, with action items going to the to-do list. Skip live recording for now. Effort M.
10. **One Google tool and an MCP shelf.** Merge Gmail (below), then add a short curated MCP list in the UI instead of more hand-written connectors. Effort S, then M for a build-a-connector skill.

## Remove or merge

- **Gmail: merge `gmail_executor` (IMAP and SMTP with an app password) and `google_gmail_executor` (shells out to the `gws` CLI) into one `gmail` tool.** Back it with the Google OAuth client Hivemind already has for Calendar and Drive (`app/services/google_workspace/oauth_client.rb`), so one "Connect Google" button covers all three and no CLI is needed. Keep a separate generic `imap` option only for non-Google mail. Fold `email_executor` (SMTP send) into the same `email` tool so there is one way to send.
- **Memory tools:** `memory_store`, `memory_update`, `memory_search`, `memory_stats` into one `memory` tool with actions. Fewer tools also helps local models, which the README says work best with 4 to 5 tools.
- **Session tools:** `sessions_list`, `sessions_history`, `sessions_send`, `session_status`, `session_search` into one `sessions` tool.
- **Background-work pairs:** `deep_research` plus `deep_research_status`, `delegate` plus `delegation_status`, `spawn` plus `spawn_status`, `coding_agent` plus `coding_agent_status` each become one tool with a status action.
- **Project tools:** `project_create`, `project_list`, `project_status`, `project_update` into one `project` tool.
- **Cron:** `cron_executor` and `cron_script_executor` into one schedule tool with a type field; one Scheduled Tasks screen.
- **HTTP:** fold `http_request` into the OpenAPI integration path so there is one way to call an API.
- **Hide in a Simple mode (do not delete):** Teams, team chat, swarm import/export, task hooks, webhook endpoints, agent channels beyond iMessage, email and one chat app, Jira, Trello, the coding agent, API tokens, budgets and analytics. Move Jira and Trello into the plugin folder.
- **Rename:** `image_executor` (reads images) and `image_generate_executor` look alike; call them `see_image` and `make_image`.

## Decisions (2026-11-07)

- First build: quote-checked research (item 1).
- Clutter: one Simple mode setting hides power-user screens and tools. Nothing is deleted. Off by default for existing installs.
- Ideas from other products are rebuilt from scratch here. No code is copied in.
- Install: keep Docker. Add a health light in the header instead of a desktop app.
- Build order after these: research library with page citations, watches, Claude and Studio router, one Google tool, then the rest of the top 10.
