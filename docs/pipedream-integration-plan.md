# Pipedream Connect Integration Plan

Give hivemind agents the largest possible tool set by integrating **Pipedream
Connect**: 2,800+ apps / 10,000+ tools through one remote MCP server, with
Pipedream running the managed OAuth for each app account. An admin drops in
their Pipedream project credentials, links the app accounts they use, and every
agent can call those tools.

## Design decisions (locked)

- **Granularity:** one `McpServer` row per enabled app (scoped via
  `x-pd-app-slug`). Reuses the existing per-app agent-assignment UI and keeps
  each agent's tool context small.
- **Identity:** a single per-install `x-pd-external-user-id` (self-hosted =
  one org). Per-user isolation is deferred until multi-tenant is a real need.
- **App discovery:** v1 = admin types the app slug (e.g. `slack`). Catalog
  browser is a later polish.

## It rides the existing MCP pipeline

`McpServer.discovered_tools` → `Mcp::ToolResolver` (exposes
`mcp_<server>_<tool>`) → `Tools::McpExecutor` → per-agent assignment. One
Pipedream app = one `McpServer` row (`metadata.provider = "pipedream"`,
`metadata.app_slug = "slack"`). ToolResolver, McpExecutor, agent assignment,
and tool exposure are **unchanged**. Only three gaps need code.

## Pipedream facts

- MCP endpoint: `https://remote.mcp.pipedream.net/v3` — JSON-RPC over
  streamable-HTTP/SSE (both supported, no config).
- Per-request headers: `Authorization: Bearer <access_token>`,
  `x-pd-project-id`, `x-pd-environment` (`development`|`production`),
  `x-pd-external-user-id`, `x-pd-app-slug`.
- Access token: `POST https://api.pipedream.com/v1/oauth/token`
  (`client_credentials` with client_id/secret), ~1 h TTL.
- Connect token (end-user account linking): minted per `external_user_id`,
  4 h / single-use, yields a hosted **Connect Link URL** — no JS/iframe needed.

## Gap 1 — standard MCP client

`Mcp::SseClient` is non-standard (`GET /tools` / `POST /tools/call`). Pipedream
needs JSON-RPC. The JSON-RPC request/response logic already exists in
`Mcp::StdioClient` (`build_jsonrpc` / response parsing) — lift it over HTTP.

- **`Mcp::PipedreamClient`** (`app/services/mcp/pipedream_client.rb`): POST
  JSON-RPC (`tools/list`, `tools/call`), parse a JSON body or `data:` SSE
  lines. Same `discover_tools`/`call_tool` surface as the other clients.
- Branch on `metadata.provider == "pipedream"` in `Tools::McpExecutor` and in
  the `connect_mcp_server` controller action.

## Gap 2 — dynamic auth (model reads static `vault:` headers today)

- **`Pipedream::TokenManager`**: mint + cache the access token (~55 min,
  `Rails.cache`); mint Connect tokens for account linking.
- `PipedreamClient` builds the 5 headers per call, pulling `app_slug` /
  `external_user_id` from `metadata` and the token from `TokenManager`. No
  schema change — `metadata` and `auth_config` jsonb already exist.

## Gap 3 — setup flows (new UX)

**A. Connect the project (one-time).** `/integrations` form for `client_id`,
`client_secret`, `project_id`, `environment`. Config in `Setting`, secret in
`VaultEntry` (namespace `pipedream`). `external_user_id` = stable per-install
id in `Setting`.

**B. Enable an app.** Admin types a slug → if the app needs OAuth, mint a
Connect token and redirect to the hosted Connect Link URL; user authorizes;
return. Then create the `McpServer` row and run `tools/list` to populate
`discovered_tools`. Key-based/no-auth apps skip the link step.

## Build order

1. `Pipedream::TokenManager` — access-token cache + connect-token mint
   (WebMock unit tests).
2. `Mcp::PipedreamClient` + `provider` branches in `McpExecutor` and the
   connect action.
3. Admin project-credentials form + `Setting`/`VaultEntry` storage.
4. "Enable app" flow: Connect Link redirect + callback → create `McpServer`,
   discover tools.
5. Reuse agent-assignment UI as-is. Later: app catalog search.

Steps 1–2 are the core (agents can call tools once a server row + token
exist); 3–4 are the UX; 5 is free.

## Security / ops

- Client secret + access tokens: vault-encrypted / `Rails.cache` only. Never in
  `discovered_tools` or logs.
- Egress allowlist must include `remote.mcp.pipedream.net` and
  `api.pipedream.com` (see `app/services/network_egress`).
- Token-refresh failure → `mark_error!` with a clear message; never silently
  return empty tools.
