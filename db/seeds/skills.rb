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
    name: "google-workspace",
    description: "Access Google Drive, Calendar, and Gmail via the gws CLI tools.",
    category: "integrations",
    content: <<~CONTENT
      # Google Workspace

      You have access to the user's Google Workspace via dedicated tools. The user connects their Google account at /integrations — tokens are managed automatically.

      ## Available Tools

      ### google_drive
      Search, read, create, and manage files in Google Drive.

      **Actions:** list, search, get, create, upload, download

      - Always search before creating — check if a file already exists
      - Use specific queries: `name contains 'Q3' and mimeType = 'application/pdf'`
      - Use `get` with a file_id to retrieve metadata (name, type, size, modified date)
      - Use `download` with `mime_type` to export Google-native files (Docs, Sheets) to PDF, CSV, etc.

      Examples:
      - `{ "action": "list" }` — list recent files
      - `{ "action": "search", "query": "name contains 'budget'" }` — find files by name
      - `{ "action": "get", "file_id": "abc123" }` — get file metadata
      - `{ "action": "create", "name": "Notes.txt", "mime_type": "text/plain" }` — create a file
      - `{ "action": "upload", "local_path": "/workspace/report.pdf" }` — upload from workspace
      - `{ "action": "download", "file_id": "abc123", "mime_type": "application/pdf" }` — export as PDF

      ### google_calendar
      List, create, update, and delete calendar events.

      **Actions:** list, get, create, update, delete, calendars

      - Always check for conflicts before creating events
      - Include timezone in event creation (defaults to UTC)
      - Use `calendars` action to list available calendars
      - Default calendar_id is "primary" if not specified

      Examples:
      - `{ "action": "list" }` — upcoming events from primary calendar
      - `{ "action": "calendars" }` — list all calendars
      - `{ "action": "create", "summary": "Team sync", "start_time": "2026-03-14T10:00:00Z", "end_time": "2026-03-14T10:30:00Z", "timezone": "America/Chicago" }` — create event
      - `{ "action": "update", "event_id": "evt123", "updates": { "summary": "Renamed meeting" } }` — update event
      - `{ "action": "delete", "event_id": "evt123" }` — delete event

      ### google_gmail
      Read, search, send, and draft emails.

      **Actions:** list, get, search, send, draft

      - **Never send emails without explicit user confirmation** — always draft first or ask before sending
      - Draft emails first, let the user review before sending
      - Use `search` with Gmail query syntax (same as the Gmail search bar)

      Examples:
      - `{ "action": "list" }` — list recent messages
      - `{ "action": "search", "query": "is:unread from:boss@company.com" }` — search inbox
      - `{ "action": "get", "message_id": "msg123" }` — read full message
      - `{ "action": "draft", "to": "alice@example.com", "subject": "Re: Project", "body": "..." }` — create draft
      - `{ "action": "send", "to": "alice@example.com", "subject": "Update", "body": "..." }` — send email

      ## Scope Awareness

      Users grant access to individual services. If a tool returns a "not authorized" error, the user needs to grant that service's permissions at /integrations. Available scopes:
      - Drive: file management
      - Calendar: event management
      - Gmail: email access (requires explicit user opt-in)
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
  },
  {
    name: "ticket-planning",
    description: "Write clear, actionable tickets — stories, bugs, tasks, and subtasks. Software-agnostic planning skill.",
    category: "project-management",
    content: <<~CONTENT
      # Ticket Planning

      You are skilled at breaking down work into clear, actionable tickets. This applies to any project management tool (Jira, Trello, Linear, GitHub Issues, etc.).

      ## Planning Workflow

      When asked to plan work for a feature or project:

      1. **Understand the goal** — Ask clarifying questions if the request is vague
      2. **Break it down** — Decompose into logical units of work
      3. **Write clear tickets** — Each ticket needs a clear title, description, and acceptance criteria
      4. **Organize hierarchy** — Group related work (epic → stories → subtasks)
      5. **Confirm before creating** — Always present the plan for approval first

      ## When to Ask Questions

      Before writing tickets, identify gaps. Ask clarifying questions when:

      - **Scope is unclear** — "Should this include mobile, or just web?"
      - **Users aren't defined** — "Who is the primary user? Admin? End user? Both?"
      - **Success criteria are missing** — "How will we know this is done? What does 'working' look like?"
      - **Edge cases aren't addressed** — "What happens if the user has no data? What if they're offline?"
      - **Dependencies are unknown** — "Does this need the new API to be deployed first?"
      - **Priority conflicts** — "This touches the same code as ticket X — should we do that first?"
      - **Design isn't specified** — "Is there a mockup, or should I propose a layout?"
      - **Performance expectations** — "How many concurrent users should this handle? Any latency targets?"
      - **Error handling** — "What should happen when [X] fails? Show an error? Retry? Fallback?"
      - **Data questions** — "Where does this data come from? How often does it update? Who owns it?"
      - **Backwards compatibility** — "Can we break the existing API, or do we need to support both?"

      **Rule of thumb:** If you're making assumptions to write the ticket, those assumptions should be questions instead.

      ## Ticket Types

      | Type | When to use |
      |------|-------------|
      | **Epic** | Large feature or initiative (contains stories) |
      | **Story** | User-facing functionality ("As a user, I can...") |
      | **Task** | Technical work that isn't directly user-facing |
      | **Bug** | Something broken that needs fixing |
      | **Sub-task** | Small unit of work under a story/task (completable in a day) |

      ## Writing Good Titles

      - Start with a verb: "Add", "Fix", "Update", "Remove", "Implement", "Create"
      - Be specific: "Add user avatar upload to agent settings" not "Avatar feature"
      - Keep under 80 characters
      - Include the component or area when helpful: "API: Add rate limiting to /users endpoint"

      ## Writing Good Descriptions

      Use this structure:

      ```
      ## Context
      [Why this work is needed — the problem or opportunity]

      ## Requirements
      - [ ] Requirement 1
      - [ ] Requirement 2

      ## Acceptance Criteria
      - [ ] AC 1: [specific, testable outcome]
      - [ ] AC 2: [specific, testable outcome]

      ## Technical Notes
      [Implementation guidance, constraints, dependencies, or relevant links]
      ```

      ### For Bugs, use:
      ```
      ## Description
      [What's happening vs. what should happen]

      ## Steps to Reproduce
      1. Step 1
      2. Step 2
      3. Step 3

      ## Expected Behavior
      [What should happen]

      ## Actual Behavior
      [What actually happens]

      ## Environment
      [Browser, OS, version, etc. if relevant]
      ```

      ## Priority Guidelines

      - **Critical/Highest** — System down, data loss, security vulnerability
      - **High** — Blocks other work, affects many users, deadline-sensitive
      - **Medium** — Standard feature work, improvements
      - **Low** — Nice to have, minor improvements
      - **Lowest** — Tech debt, cleanup, future considerations

      ## Estimation Guidelines

      When estimating work:
      - **Small (S)** — A few hours, straightforward, well-understood
      - **Medium (M)** — 1-2 days, some complexity or unknowns
      - **Large (L)** — 3-5 days, significant complexity, may need design
      - **X-Large (XL)** — More than a week — should be broken down further

      If a ticket feels XL, it's probably an epic that needs decomposition.

      ## Best Practices

      - **One concern per ticket** — Don't bundle unrelated work
      - **Subtasks should be completable in a day** — If not, break them down more
      - **Acceptance criteria are testable** — "Works correctly" is not testable; "Returns 200 with JSON body containing user.name" is
      - **Link dependencies** — Note if ticket A must be done before ticket B
      - **Label consistently** — Use labels like "frontend", "backend", "infrastructure", "docs", "design"
      - **Include context** — Future-you (or someone else) needs to understand why, not just what
      - **Don't over-specify implementation** — Describe the outcome, not every line of code
    CONTENT
  },
  {
    name: "work_on_task",
    description: "Task hook skill: work through an assigned task and move it to review when done.",
    category: "automation",
    content: <<~CONTENT
      # Work On Task

      You have been assigned a task from the team task board. A hook fired because this task was moved to `in_progress`.

      ## Your Job

      1. **Read the task details carefully** — title, description, checklist, comments, and dependencies are all provided above.
      2. **Do the work** — Use your tools to complete the task. Follow the description and checklist items.
      3. **Check off checklist items** as you complete them using `task_manager` with `update_checklist` / `toggle`.
      4. **When finished**, do TWO things:
         a. **Add a summary comment** to the task using `task_manager` with `add_comment` — explain what you did, what files you changed, any decisions you made, and anything the reviewer should know.
         b. **Move the task to `review`** using `task_manager` with `move` action and status `review`.

      ## Rules

      - **Stay focused on this task only.** Do not go looking for other work.
      - **If you get blocked**, add a comment explaining the blocker and stop. Do NOT move to review.
      - **If the task description is unclear**, add a comment asking for clarification and stop. Do NOT guess.
      - **Be thorough.** Check your work before moving to review.
      - **Your summary comment is your deliverable.** The reviewer will read it to understand what was done.
    CONTENT
  },
  {
    name: "deep_research",
    description: "Perform thorough, multi-step research on any topic with web search, source analysis, and synthesized reports.",
    category: "utilities",
    content: <<~CONTENT
      # Deep Research

      Use the `deep_research` tool for comprehensive, multi-step research tasks.

      ## When to Use
      - Complex questions requiring multiple sources
      - Market research, competitive analysis
      - Technical deep-dives and comparisons
      - Literature reviews and topic exploration
      - Current events and trend analysis

      ## Parameters
      - **query** (required): The research question or topic
      - **depth**: quick (5 searches), standard (12 searches), deep (25 searches)
      - **focus**: general, technical, scientific, news, financial
      - **output_format**: report, bullet_points, detailed_analysis, executive_summary

      ## Workflow
      1. Call `deep_research` with your query — returns immediately with a task_key
      2. The research runs in the background (plan → search → analyze → iterate → synthesize)
      3. Use `deep_research_status` with the task_key to check progress
      4. Results are automatically injected into the conversation when complete

      ## Tips
      - Use "deep" depth for thorough investigations
      - Use "quick" depth for simple fact-checking
      - Use "executive_summary" format for decision-makers
      - You can cancel active research with `deep_research_status` action: cancel
    CONTENT
  }
]

# Map skill names to their required tool names
SKILL_TOOL_MAP = {
  "github" => [ "shell" ],
  "weather" => [ "web_fetch" ],
  "trello" => [ "http_request" ],
  "notion" => [ "http_request" ],
  "summarize" => [ "web_fetch", "pdf_read", "file_read" ],
  "google-workspace" => [ "google_drive", "google_calendar", "google_gmail" ],
  "docker" => [ "shell" ],
  "git" => [ "shell", "file_read", "file_write", "file_edit" ],
  "ticket-planning" => [ "ask_user", "file_read", "web_fetch" ],
  "work_on_task" => [ "task_manager", "shell", "file_read", "file_write", "file_edit", "web_fetch", "web_search", "grep", "glob" ],
  "deep_research" => [ "deep_research", "deep_research_status", "web_search", "web_fetch" ]
}.freeze

skills.each do |attrs|
  skill = Skill.find_or_initialize_by(name: attrs[:name])
  skill.assign_attributes(attrs.merge(builtin: true, enabled: true))
  skill.summary = attrs[:description].to_s.truncate(200) if skill.summary.blank?
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
