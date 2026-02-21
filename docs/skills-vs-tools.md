# Skills vs Tools

When to create a skill, a tool, or both.

## TL;DR

| Need | Use |
|------|-----|
| Agent needs **instructions** on how to do something | **Skill** |
| Agent needs to **call an API** with stored credentials | **Tool** (executor) |
| Agent needs both guidance and API access | **Skill + Tool** |

## Skills

Skills are **text instructions** injected into the agent's system prompt. They tell the agent _how_ to approach a task — what to do, what patterns to follow, what conventions to use.

**Use a skill when:**
- The agent needs domain knowledge or workflow guidance
- The task can be accomplished with existing tools (shell, file_read, http_request, etc.)
- No secrets or credentials are needed
- You want to teach the agent a process, not give it a new capability

**Examples:**
- Code review guidelines
- Git branching conventions
- How to structure a blog post
- Project-specific domain knowledge

**Skills live in:** `Skill` model in the database, assigned to agents via `skills_config`

## Tools

Tools are **server-side executors** that run Ruby code on behalf of the agent. The agent calls the tool with parameters, and the executor handles everything (API calls, auth, formatting).

**Use a tool when:**
- The agent needs to interact with an external API that requires authentication
- Credentials are stored in the vault (vault values are **always redacted** from agents)
- You need server-side logic (pagination, error handling, response formatting)
- The agent shouldn't (or can't) handle the raw HTTP details

**Examples:**
- `jira` — Jira Cloud API with Basic auth
- `trello` — Trello API with key/token auth
- `gmail` — IMAP/SMTP with app passwords
- `image_generate` — OpenAI DALL-E with Bearer token

**Tools require 4 things:**
1. **Executor class** — `app/services/tools/<name>_executor.rb` (extends `BaseExecutor`)
2. **Registration** — Add to `EXECUTORS` hash in `app/services/tools/executor.rb`
3. **Validation** — Add executor type to `Tool` model's `executor_type` inclusion list
4. **Seed** — Add tool definition to `db/seeds/tools.rb`

## ⚠️ The Vault Rule

**Vault entries are NEVER exposed to agents in plain text.** The `VaultExecutor` always returns redacted values (prefix + last 4 chars). This is by design — it prevents credential leakage through prompt injection or careless tool use.

This means:
- ❌ A skill that says "read the vault and put the API key in the URL" **will not work**
- ❌ An agent using `http_request` raw mode with vault credentials **will not work**
- ✅ A tool executor that reads vault server-side and injects credentials **will work**

If your integration needs stored credentials → **you need a tool executor**.

## Skill + Tool Together

Often the best approach is both:
- **Tool** handles the API calls and auth
- **Skill** teaches the agent _when_ and _how_ to use the tool effectively

Example: The `trello` tool provides the API actions, and the `trello` skill tells the agent about board structure, card conventions, and workflow patterns.

## Quick Decision Tree

```
Does it need stored credentials (vault)?
  ├─ YES → Build a tool executor
  │         Also need workflow guidance? → Add a skill too
  └─ NO → Can existing tools handle it?
           ├─ YES → Write a skill (instructions only)
           └─ NO → Build a tool executor
```

## Creating a New Tool

1. Create `app/services/tools/<name>_executor.rb` extending `BaseExecutor`
2. Add to `EXECUTORS` in `app/services/tools/executor.rb`
3. Add to `executor_type` validation in `app/models/tool.rb`
4. Add seed definition in `db/seeds/tools.rb`
5. Read credentials with `VaultEntry.find_by(namespace:, key:)&.value`
6. Rebuild containers: `docker compose build app worker`
7. Seed: `docker compose exec app bash -c 'bundle exec rails db:seed'`
8. Assign tool to agents

## Creating a New Skill

1. Create a `Skill` record (via UI or Rails console) with name and content (markdown)
2. Assign to agents via their `skills_config`
3. No rebuild needed — skills are loaded from DB at runtime
