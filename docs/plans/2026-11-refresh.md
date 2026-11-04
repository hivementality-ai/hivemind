# Hivemind refresh: fast, reliable, connects to anything

Status: plan, 2026-11-03. Each numbered item is one PR. Ship order is top to bottom
within a phase; phases 1 and 2 can run in parallel.

Ground rules

- Nothing user-facing is removed. Hivemind is open source and every feature stays.
  Rarely used subsystems become off-by-default and lazy (no boot or per-turn cost
  until switched on). Only dead code is deleted.
- Every change ships through `hivemind update` from a release tag.
- Two brains are first class: Claude (subscription via sdk-proxy, or API key) and any
  OpenAI-compatible local server (for example oMLX on a Mac Studio).
- Pipedream Connect (PR #440, "Add Pipedream Connect integration and vault entries
  UI") is not the direction. Hivemind builds its own connectors (phase 3). The vault
  entries UI from that branch is worth salvaging into 3.3.

## Phase 0: safe updates (first, everything else rides on it)

0.1 `hivemind update` backs up the database before migrating, fails loudly on a
    migration error instead of restarting anyway (`bin/hivemind:254`), pulls
    sdk-proxy and browser-sidecar too, and waits for health before reporting success.
0.2 Health checks for app (`/up`) and both Sidekiq workers in compose; set
    `stop_grace_period: 30s` so updates stop killing turns mid-reply.
0.3 RSpec refuses to run against a production `DATABASE_URL` (#443, "RSpec in the
    production Compose container can wipe the live database").
0.4 `npm ci` in the connector and sdk-proxy images (#446, "Connector/sdk-proxy Docker
    images run unlocked npm install instead of the lockfile").

## Phase 1: speed

1.1 Interactive queue: user chats get their own Sidekiq queue with reserved threads;
    heartbeats, schedules, sub-agents and coding jobs stay on `agents`
    (`config/sidekiq_agents.yml:7`).
1.2 Stream through the tool loop: `Agents::ToolLoop` passes a block to
    `adapter.chat` (`tool_loop.rb:148`); the OpenAI-compatible stream parser learns to
    accumulate `tool_calls` deltas (`openai_compatible_adapter.rb:145-268`).
1.3 Token streaming on the Claude subscription path: `includePartialMessages` and
    `stream_event` handling in `sdk-proxy/server.js:278`.
1.4 Stable prompt cache: deterministic tool list order, cache breakpoint on the
    last message as well as the system prompt (`anthropic_adapter.rb:152-161`).
1.5 Background bookkeeping off the main model: memory extraction, summaries and
    consolidation run on a cheap model (Haiku or the local brain), not Opus, and never
    spawn an extra sdk-proxy process per turn.
1.6 Memory recall gets a 2-3s timeout and skips on failure
    (`embeddings/ollama_adapter.rb:20`); embeddings fall back cleanly when Ollama is
    absent.
1.7 Small costs: no Redis read per token (`chat_stream_job.rb:184`), Puma threads up
    so tool callbacks don't starve the UI, vendor `marked` instead of the CDN.
1.8 Warm Claude process per session in sdk-proxy (largest item, last).

## Phase 2: reliability and the second brain

2.1 OpenAI-compatible errors are classified and retried once on connection faults,
    with a separate first-token timeout (#444, "OpenAI-compatible adapter drops the
    turn on a single TCP timeout").
2.2 Provider picked by id, not adapter type, so oMLX, Laya and OpenRouter can coexist
    (`agents/_form.html.erb:94`, `providers/resolver.rb:23`).
2.3 Brain picker per chat: nullable provider and model on sessions and projects,
    resolved session > project > agent, dropdown in the chat header. "Auto" can route
    through Laya later.
2.4 Real failover: a global default chain (Claude then local) that keeps tools; on
    fallback from the sdk-proxy path, switch to `ToolLoop` with real tool definitions
    (`chat_stream_job.rb:171`, `failover_adapter.rb`).
2.5 Stuck-turn sweep on boot clears stale processing flags and posts "turn
    interrupted, retry"; per-session lock so two turns never overwrite each other
    (`chat_stream_job.rb:212-217`).
2.6 Timeouts on sdk-proxy tool callbacks (`mcp-tool-bridge.js:106`).
2.7 Team chat wakes on @mentions again (#445, "Team chat stays idle during work and
    @mentions in agent replies never wake teammates").

## Phase 3: connect to anything, built by Hivemind itself

The idea: she says "connect my Notion" and Hivemind does the work. A connector is
data, not generated Ruby, so a bad one can never break the app.

3.1 Make MCP work: call `Mcp::ToolResolver` from tool resolution, replace the fake
    `sse` transport with real Streamable HTTP (initialize handshake, session id, SSE
    parsing), keep stdio servers alive between calls, and add the missing MCP screen.
3.2 One-click remote MCP with OAuth: discovery, dynamic client registration, PKCE,
    refresh, tokens in the vault, callback on localhost. Written from the public MCP
    authorization spec, not copied from any closed codebase. LAN and localhost
    servers allowed.
3.3 Connector model plus vault references: a `Connector` record holds base URL, auth
    scheme (key, bearer, basic, OAuth2), and a list of operations. Secrets live in the
    vault and are referenced by name, so agent-made tools stop being banned from
    authenticated APIs (`agents/tool_creator.rb`). Salvage the vault UI from PR #440.
3.4 Connector builder skill: given an app name, Hivemind (1) checks the catalog for an
    official MCP server and offers one-click connect, else (2) finds the app's API
    docs or OpenAPI spec, drafts a connector, (3) walks her through sign-in, (4) runs a
    read-only probe call, and (5) saves only after the probe passes. She approves
    before anything is saved.
3.5 Self-repair: when a connector's calls start failing, Hivemind proposes a fix to the
    definition and asks before applying it.
3.6 Tool search: connectors and MCP tools are offered through `find_tools` /
    `use_tool` so hundreds of actions don't flood the prompt (matters most on the
    local brain).
3.7 Starter catalog and imports: cards for official remote MCP servers (Notion,
    Linear, GitHub, Atlassian, Asana, Stripe, Sentry), Google via the existing OAuth
    with a guided setup, and a one-click import of Claude Desktop's `mcpServers`.
    Connectors can be exported and shared, so the open-source community grows the
    catalog.

## Phase 4: settings that are old or horrible

4.1 Settings audit: walk every settings and integration page, list what is
    confusing, stale or broken (for example rclone token pasting, the Google Cloud
    client ID step, 161 agent templates in one list), and fix in small PRs.
4.2 Lazy subsystems: channels connector, signal-cli, Discord gateway, heartbeat,
    update check, remote access health check, audit logging start only when switched on.
    Templates grouped and searchable instead of one long list.
4.3 Dead code out: Solid Queue/Cable/Cache leftovers, legacy `lib/connector`,
    `browser-sidecar/server.js` (and fix the dev override that points at it),
    `kamal` gem.
