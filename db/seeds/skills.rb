# frozen_string_literal: true

puts "Seeding Built-in Skills..."

skills = [
  {
    name: "github",
    description: "Interact with GitHub using the gh CLI for issues, PRs, CI runs, and API queries.",
    category: "coding",
    content: <<~CONTENT
      # GitHub

      Use the `gh` CLI (GitHub CLI) for all GitHub operations. It's pre-authenticated.

      ## Common Commands
      - `gh issue list` — list issues
      - `gh issue create --title "..." --body "..."` — create issue
      - `gh pr list` — list pull requests
      - `gh pr create --title "..." --body "..." --base main` — create PR
      - `gh pr view <number>` — view PR details
      - `gh pr merge <number>` — merge PR
      - `gh run list` — list CI runs
      - `gh run view <id>` — view CI run details
      - `gh api <endpoint>` — raw API calls

      ## Workflow
      1. Use shell tool to run gh commands
      2. Parse output for structured data
      3. For complex queries, use `gh api` with GraphQL
    CONTENT
  },
  {
    name: "weather",
    description: "Get current weather and forecasts using wttr.in (no API key required).",
    category: "utilities",
    content: <<~CONTENT
      # Weather

      Use wttr.in for weather data. No API key needed.

      ## Commands (via shell or web_fetch)
      - `curl wttr.in/CityName?format=j1` — JSON weather data
      - `curl wttr.in/CityName?format=3` — one-line summary
      - `curl wttr.in/CityName` — full forecast (text)

      ## Tips
      - Use `?format=j1` for structured JSON you can parse
      - Supports city names, zip codes, airport codes, IP-based location
      - For forecasts: `wttr.in/City?format=j1` includes 3-day forecast
    CONTENT
  },
  {
    name: "trello",
    description: "Manage Trello boards, lists, and cards via REST API.",
    category: "productivity",
    content: <<~CONTENT
      # Trello

      Use the http_request tool to interact with Trello's REST API.

      ## Authentication
      Requires API key and token. Store in vault as `trello/api_key` and `trello/token`.
      Get them at: https://trello.com/power-ups/admin

      ## Common Endpoints
      - GET `/1/members/me/boards` — list boards
      - GET `/1/boards/{id}/lists` — list columns
      - GET `/1/lists/{id}/cards` — list cards
      - POST `/1/cards` — create card (idList, name, desc)
      - PUT `/1/cards/{id}` — update card
      - POST `/1/cards/{id}/actions/comments` — add comment

      ## All requests need
      `?key={api_key}&token={token}` appended to the URL.
      Base URL: `https://api.trello.com`
    CONTENT
  },
  {
    name: "notion",
    description: "Create and manage Notion pages, databases, and blocks via API.",
    category: "productivity",
    content: <<~CONTENT
      # Notion

      Use the http_request tool to interact with the Notion API.

      ## Authentication
      Store integration token in vault as `notion/api_token`.
      Create at: https://www.notion.so/my-integrations

      ## Headers
      - Authorization: Bearer {token}
      - Notion-Version: 2022-06-28
      - Content-Type: application/json

      ## Common Endpoints
      - POST `/v1/search` — search pages and databases
      - GET `/v1/databases/{id}/query` — query database
      - POST `/v1/pages` — create page
      - PATCH `/v1/pages/{id}` — update page properties
      - GET `/v1/blocks/{id}/children` — get page content
      - PATCH `/v1/blocks/{id}/children` — append content

      Base URL: `https://api.notion.com`
    CONTENT
  },
  {
    name: "summarize",
    description: "Summarize or extract text from URLs, articles, and documents.",
    category: "utilities",
    content: <<~CONTENT
      # Summarize

      Summarize content from various sources.

      ## Workflow
      1. Use `web_fetch` tool to get the content from a URL
      2. For PDFs, use `pdf_read` tool first
      3. For uploaded files, use `file_read` tool
      4. Summarize the extracted text

      ## Guidelines
      - Start with a 1-2 sentence TL;DR
      - Follow with key points as bullet list
      - Include notable quotes or data points
      - Note the source and date if available
      - Adapt length to content: short articles get short summaries
    CONTENT
  },
  {
    name: "google-calendar",
    description: "Manage Google Calendar events, check availability, and schedule meetings.",
    category: "productivity",
    content: <<~CONTENT
      # Google Calendar

      Use the http_request tool with Google Calendar API.

      ## Authentication
      Store OAuth token in vault as `google/calendar_token`.

      ## Common Endpoints (base: https://www.googleapis.com/calendar/v3)
      - GET `/calendars/primary/events?timeMin={ISO}&timeMax={ISO}` — list events
      - POST `/calendars/primary/events` — create event
      - PUT `/calendars/primary/events/{id}` — update event
      - DELETE `/calendars/primary/events/{id}` — delete event
      - GET `/freeBusy` — check availability

      ## Event Body
      ```json
      {
        "summary": "Meeting title",
        "start": { "dateTime": "2026-01-01T09:00:00-06:00" },
        "end": { "dateTime": "2026-01-01T10:00:00-06:00" },
        "attendees": [{ "email": "person@example.com" }]
      }
      ```
    CONTENT
  },
  {
    name: "docker",
    description: "Manage Docker containers, images, and compose stacks.",
    category: "coding",
    content: <<~CONTENT
      # Docker

      Use the shell tool for Docker operations.

      ## Common Commands
      - `docker ps` — running containers
      - `docker ps -a` — all containers
      - `docker logs <container> --tail 50` — recent logs
      - `docker exec -it <container> <cmd>` — run command in container
      - `docker compose up -d` — start stack
      - `docker compose down` — stop stack
      - `docker compose build <service>` — rebuild service
      - `docker compose restart <service>` — restart service
      - `docker images` — list images
      - `docker system df` — disk usage

      ## Tips
      - Always use `--tail` with logs to avoid overwhelming output
      - Use `docker compose exec` for running containers (no -it needed)
      - Check `docker compose ps` before rebuilding
    CONTENT
  },
  {
    name: "git",
    description: "Git version control workflows — branching, committing, rebasing, and PR management.",
    category: "coding",
    content: <<~CONTENT
      # Git

      Use the shell tool for git operations.

      ## Workflow
      1. `git status` — always check status first
      2. `git checkout -b feat/description` — create feature branch
      3. Make changes with file_edit/file_write
      4. `git add -A` — stage changes
      5. `git commit -m "type: description"` — commit with conventional message
      6. `git push origin HEAD` — push branch

      ## Commit Message Format
      - `feat:` new feature
      - `fix:` bug fix
      - `refactor:` code restructure
      - `docs:` documentation
      - `test:` test additions
      - `chore:` maintenance

      ## Tips
      - `git diff` before committing to review changes
      - `git log --oneline -10` for recent history
      - `git stash` / `git stash pop` for temporary saves
      - Never force-push to main/master
    CONTENT
  }
]

# Map skill names to their required tool names
SKILL_TOOL_MAP = {
  "github" => ["shell"],
  "weather" => ["web_fetch"],
  "trello" => ["http_request"],
  "notion" => ["http_request"],
  "summarize" => ["web_fetch", "pdf_read", "file_read"],
  "google-calendar" => ["http_request"],
  "docker" => ["shell"],
  "git" => ["shell", "file_read", "file_write", "file_edit"]
}.freeze

skills.each do |attrs|
  skill = Skill.find_or_initialize_by(name: attrs[:name])
  skill.assign_attributes(attrs.merge(builtin: true, enabled: true))
  skill.save!

  # Wire up required tools
  if (tool_names = SKILL_TOOL_MAP[skill.name])
    tool_names.each do |tool_name|
      tool = Tool.find_by(name: tool_name)
      next unless tool

      SkillTool.find_or_create_by(skill: skill, tool: tool)
    end
  end

  tool_count = skill.tools.count
  puts "  ✓ #{skill.name}#{tool_count > 0 ? " (#{tool_count} tools)" : ''}"
end

puts "Built-in Skills seeded!"
