# frozen_string_literal: true

puts "Seeding Built-in Tools..."

BUILTIN_TOOLS = [
  {
    name: "shell",
    description: "Execute a shell command in the workspace container. Use for running scripts, installing packages, checking system info, compiling code, etc.",
    executor_type: "shell",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "command" => { "type" => "string", "description" => "The shell command to execute" }
      },
      "required" => [ "command" ]
    }
  },
  {
    name: "sleep",
    description: "Pause execution for a specified number of seconds (max 180). Use this when you need to wait for an external process to finish, a deployment to complete, or any situation where you need to stall before checking status again.",
    executor_type: "sleep",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "seconds" => { "type" => "integer", "description" => "Number of seconds to wait (1-180)" },
        "reason" => { "type" => "string", "description" => "Why you're waiting (shown in the chat UI)" }
      },
      "required" => [ "seconds" ]
    }
  },
  {
    name: "file_read",
    description: "Read the contents of a file in the workspace.",
    executor_type: "file_read",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "path" => { "type" => "string", "description" => "Path to the file to read" }
      },
      "required" => [ "path" ]
    }
  },
  {
    name: "file_write",
    description: "Write content to a file in the workspace. Creates parent directories if needed.",
    executor_type: "file_write",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "path" => { "type" => "string", "description" => "Path to write the file" },
        "content" => { "type" => "string", "description" => "Content to write to the file" }
      },
      "required" => [ "path", "content" ]
    }
  },
  {
    name: "file_send",
    description: "Send a file from the workspace to the chat. Use this to share files you've created (reports, images, data files, etc) with the user.",
    executor_type: "file_send",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "path" => { "type" => "string", "description" => "Path to the file in workspace" },
        "filename" => { "type" => "string", "description" => "Optional: custom filename (defaults to basename)" }
      },
      "required" => [ "path" ]
    }
  },
  {
    name: "web_search",
    description: "Search the web for information. Returns relevant results with titles, URLs, and snippets.",
    executor_type: "web_search",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "query" => { "type" => "string", "description" => "Search query" },
        "count" => { "type" => "integer", "description" => "Number of results to return (default: 5, max: 10)" },
        "country" => { "type" => "string", "description" => "2-letter country code for regional results (e.g. US, GB, DE)" },
        "language" => { "type" => "string", "description" => "ISO language code for results (e.g. en, fr, de)" }
      },
      "required" => [ "query" ]
    }
  },
  {
    name: "web_fetch",
    description: "Fetch and extract readable content from a URL. Returns the page content as text.",
    executor_type: "web_fetch",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "url" => { "type" => "string", "description" => "URL to fetch" }
      },
      "required" => [ "url" ]
    }
  },
  {
    name: "browser",
    description: "Navigate and interact with web pages using a real browser (JavaScript rendering). Supports multi-step interactions: click, type, scroll, keyboard shortcuts, screenshots, and text extraction. Use when web_fetch fails on JS-heavy sites or when you need to fill forms, click buttons, or do multi-step flows.",
    executor_type: "browser",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => {
          "type" => "string",
          "description" => "Browser action to perform",
          "enum" => [ "navigate", "state", "click", "type", "scroll", "keys", "screenshot", "extract", "done" ]
        },
        "url" => { "type" => "string", "description" => "URL to navigate to (required for navigate action)" },
        "index" => { "type" => "integer", "description" => "Element index from state response (required for click/type actions)" },
        "text" => { "type" => "string", "description" => "Text to type (required for type action)" },
        "clear" => { "type" => "boolean", "description" => "Clear field before typing (default: true)" },
        "direction" => { "type" => "string", "description" => "Scroll direction: up or down (default: down)", "enum" => [ "up", "down" ] },
        "pages" => { "type" => "number", "description" => "Number of pages to scroll (default: 1.0)" },
        "keys" => { "type" => "string", "description" => "Keyboard keys to send (e.g. Enter, Escape, Control+a)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "memory_search",
    description: "Search your memories for past conversations and knowledge. Use to recall previous interactions, decisions, or context.",
    executor_type: "memory_search",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "query" => { "type" => "string", "description" => "What to search for in your memories" },
        "limit" => { "type" => "integer", "description" => "Max results to return (1-20, default 10)" }
      },
      "required" => [ "query" ]
    }
  },
  {
    name: "file_edit",
    description: "Make a precise find-and-replace edit in a file. The old_text must match exactly once. Use for surgical code changes.",
    executor_type: "file_edit",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "path" => { "type" => "string", "description" => "Path to the file to edit" },
        "old_text" => { "type" => "string", "description" => "Exact text to find (must match once)" },
        "new_text" => { "type" => "string", "description" => "Replacement text" }
      },
      "required" => %w[path old_text new_text]
    }
  },
  {
    name: "image",
    description: "Analyze an image using a vision model (GPT-4.1 or Claude). Describe contents, read text, extract data from screenshots.",
    executor_type: "image",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "image" => { "type" => "string", "description" => "URL of the image to analyze" },
        "prompt" => { "type" => "string", "description" => "What to analyze or ask about the image (default: describe it)" }
      },
      "required" => [ "image" ]
    }
  },
  {
    name: "image_generate",
    description: "Generate an image using DALL-E 3. Creates high-quality images from text prompts and sends them to chat.",
    executor_type: "image_generate",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "prompt" => { "type" => "string", "description" => "Description of the image to generate" },
        "size" => { "type" => "string", "description" => "Image size: 1024x1024 (square), 1792x1024 (landscape), or 1024x1792 (portrait). Default: 1024x1024", "enum" => [ "1024x1024", "1792x1024", "1024x1792" ] }
      },
      "required" => [ "prompt" ]
    }
  },
  {
    name: "cron",
    description: "Manage scheduled tasks. When a task fires, a new agent session is created and the agent receives the prompt with full access to all its tools (gmail, web_search, etc.). This is NOT a shell cron — it's an agent turn.",
    executor_type: "cron",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: list, create, confirm_create, delete, run", "enum" => %w[list create confirm_create delete run] },
        "name" => { "type" => "string", "description" => "Task name (for create)" },
        "schedule" => { "type" => "string", "description" => "Cron expression, e.g. '0 13 * * *' for 8am CT (for create)" },
        "prompt" => { "type" => "string", "description" => "Instructions for the agent to execute when the task fires. The agent wakes up in a new session with this prompt and can use all its tools (gmail, web_search, etc.)." },
        "confirmation_id" => { "type" => "string", "description" => "Confirmation ID returned by create action (for confirm_create)" },
        "task_id" => { "type" => "string", "description" => "Task ID (for delete/run)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "cron_script",
    description: "Schedule scripts to run on a cron schedule. Instead of a prompt, point to a script file (Python, Ruby, or Shell) that runs in the workspace. Gives agents a bigger playground for complex scheduled tasks.",
    executor_type: "cron_script",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: list, create, confirm_create, delete, run, update_script", "enum" => %w[list create confirm_create delete run update_script] },
        "name" => { "type" => "string", "description" => "Task name (for create)" },
        "schedule" => { "type" => "string", "description" => "Cron expression, e.g. '0 9 * * *' (for create)" },
        "script_path" => { "type" => "string", "description" => "Path to the script file in workspace, e.g. /workspace/scripts/daily_report.py (for create/update_script)" },
        "task_id" => { "type" => "string", "description" => "Task ID (for delete/run/update_script)" },
        "confirmation_id" => { "type" => "string", "description" => "Confirmation ID returned by create action (for confirm_create)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "message",
    description: "Send messages via connected channels (Discord, Slack, Telegram, WhatsApp, Signal). Can also list available channels and react to messages.",
    executor_type: "message",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: send, list_channels, react", "enum" => %w[send list_channels react] },
        "channel" => { "type" => "string", "description" => "Channel type or name (discord, slack, telegram, whatsapp, signal)" },
        "to" => { "type" => "string", "description" => "Recipient (chat ID, channel ID, phone number)" },
        "message" => { "type" => "string", "description" => "Message content" },
        "message_id" => { "type" => "string", "description" => "Message ID (for react)" },
        "emoji" => { "type" => "string", "description" => "Emoji to react with" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "heartbeat_write",
    description: "Add, remove, or list tasks on the heartbeat checklist. The system assistant processes this checklist on each heartbeat cycle.",
    executor_type: "heartbeat_write",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: add, remove, list, clear", "enum" => %w[add remove list clear] },
        "task" => { "type" => "string", "description" => "Task description (for add/remove)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "delegate",
    description: "Delegate a task to another agent. They work independently in their own session and report back when done. Use delegation_status to check progress. Best for tasks that take time (research, coding, projects).",
    executor_type: "delegate",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "agent" => { "type" => "string", "description" => "Name of the agent to delegate to" },
        "task" => { "type" => "string", "description" => "Task or question for the agent" }
      },
      "required" => %w[agent task]
    }
  },
  {
    name: "delegation_status",
    description: "Check the status of a delegated task, or list recent delegations.",
    executor_type: "delegation_status",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: status (check one task) or list (show recent tasks)", "enum" => %w[status list] },
        "task_key" => { "type" => "string", "description" => "Task ID from delegate (for status action)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "sessions_list",
    description: "List active sessions with their agents, message counts, and last activity.",
    executor_type: "sessions_list",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "limit" => { "type" => "integer", "description" => "Max results (1-50, default 20)" },
        "status" => { "type" => "string", "description" => "Filter by status (active, completed, archived)" }
      },
      "required" => []
    }
  },
  {
    name: "sessions_send",
    description: "Send a message into another session by session_key or agent name. The target agent processes it and returns a reply.",
    executor_type: "sessions_send",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "session_key" => { "type" => "string", "description" => "Target session key" },
        "agent" => { "type" => "string", "description" => "Agent name (finds their most recent session)" },
        "message" => { "type" => "string", "description" => "Message to send" }
      },
      "required" => [ "message" ]
    }
  },
  {
    name: "sessions_history",
    description: "Fetch the message history of a session by session_key.",
    executor_type: "sessions_history",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "session_key" => { "type" => "string", "description" => "Session key to fetch history for" },
        "limit" => { "type" => "integer", "description" => "Number of recent messages (1-50, default 20)" }
      },
      "required" => [ "session_key" ]
    }
  },
  {
    name: "session_status",
    description: "Show status and usage stats for a session — tokens, cost, request count, models used.",
    executor_type: "session_status",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "session_key" => { "type" => "string", "description" => "Session key (optional — defaults to your most recent session)" }
      },
      "required" => []
    }
  },
  {
    name: "agents_list",
    description: "List all available agents with their roles, models, teams, and tool counts.",
    executor_type: "agents_list",
    requires_approval: false,
    parameters_schema: {
      "properties" => {},
      "required" => []
    }
  },
  {
    name: "gateway",
    description: "Platform management — check system status, view config, restart services.",
    executor_type: "gateway",
    requires_approval: true,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: status, restart, config", "enum" => %w[status restart config] },
        "service" => { "type" => "string", "description" => "Service to restart (rails, sidekiq)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "tts",
    description: "Convert text to speech using OpenAI's TTS API. Returns an audio file path.",
    executor_type: "tts",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "text" => { "type" => "string", "description" => "Text to convert to speech (max 4096 chars)" },
        "voice" => { "type" => "string", "description" => "Voice: alloy, echo, fable, onyx, nova, shimmer", "enum" => %w[alloy echo fable onyx nova shimmer] }
      },
      "required" => [ "text" ]
    }
  },
  {
    name: "gmail",
    description: "Read, search, and send Gmail emails. Uses IMAP/SMTP with App Password — no API setup needed.",
    executor_type: "gmail",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: inbox, search, get, send, reply", "enum" => %w[inbox search get send reply] },
        "query" => { "type" => "string", "description" => "Search query (for search)" },
        "uid" => { "type" => "string", "description" => "Email UID (for get/reply)" },
        "to" => { "type" => "string", "description" => "Recipient email (for send)" },
        "subject" => { "type" => "string", "description" => "Email subject (for send)" },
        "body" => { "type" => "string", "description" => "Email body (for send/reply)" },
        "folder" => { "type" => "string", "description" => "IMAP folder (default: INBOX)" },
        "limit" => { "type" => "integer", "description" => "Max results (default: 10)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "cloud_storage",
    description: "Access cloud storage (Google Drive, S3, Dropbox, OneDrive, B2, SFTP) via rclone. List remotes, browse files, upload, download, sync. Configure at /integrations.",
    executor_type: "cloud_storage",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: remotes, list, search, read, download, upload, sync, copy, mkdir, delete, info, about", "enum" => %w[remotes list search read download upload sync copy mkdir delete info about] },
        "remote" => { "type" => "string", "description" => "Remote name (optional — uses first configured if omitted)" },
        "path" => { "type" => "string", "description" => "File/folder path on remote" },
        "query" => { "type" => "string", "description" => "Search query (for search)" },
        "local_path" => { "type" => "string", "description" => "Local file path (for upload)" },
        "source" => { "type" => "string", "description" => "Source path (for sync/copy)" },
        "dest" => { "type" => "string", "description" => "Destination path" },
        "limit" => { "type" => "integer", "description" => "Max results (default: 20)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "http_request",
    description: "Make HTTP requests to external APIs. Can use registered API integrations (with stored credentials and OpenAPI specs) or make raw requests to any URL. Supports GET, POST, PUT, PATCH, DELETE. Use list_apis to see available integrations, list_endpoints to explore an API's endpoints.",
    executor_type: "http_request",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: request, list_apis, list_endpoints", "enum" => [ "request", "list_apis", "list_endpoints" ] },
        "integration" => { "type" => "string", "description" => "Name of a registered API integration (optional — omit for raw requests)" },
        "method" => { "type" => "string", "description" => "HTTP method (GET, POST, PUT, PATCH, DELETE)", "enum" => [ "GET", "POST", "PUT", "PATCH", "DELETE" ] },
        "url" => { "type" => "string", "description" => "Full URL for raw requests, or endpoint path for integration requests" },
        "path" => { "type" => "string", "description" => "Endpoint path (alias for url when using integration)" },
        "operation_id" => { "type" => "string", "description" => "Match endpoint by operationId from the OpenAPI spec" },
        "headers" => { "type" => "object", "description" => "Additional request headers" },
        "query" => { "type" => "object", "description" => "Query parameters" },
        "body" => { "type" => "object", "description" => "Request body (auto JSON-encoded)" },
        "timeout" => { "type" => "integer", "description" => "Request timeout in seconds (default: 30, max: 120)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "jira",
    description: "Manage Jira issues and projects. Search, create, update, comment, transition, and assign issues. Supports JQL queries for advanced filtering.",
    executor_type: "jira",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action to perform", "enum" => %w[get_issue search create_issue update_issue add_comment list_comments transition list_transitions assign list_projects my_issues] },
        "key" => { "type" => "string", "description" => "Issue key (e.g., PROJ-123). Required for: get_issue, update_issue, add_comment, list_comments, transition, list_transitions, assign" },
        "jql" => { "type" => "string", "description" => "JQL query string for search action (e.g., 'project = PROJ AND status = Open')" },
        "project" => { "type" => "string", "description" => "Project key for create_issue (e.g., PROJ)" },
        "summary" => { "type" => "string", "description" => "Issue title for create_issue or update_issue" },
        "description" => { "type" => "string", "description" => "Issue description (plain text, converted to Jira format)" },
        "issue_type" => { "type" => "string", "description" => "Issue type for create_issue (default: Task). Common: Task, Bug, Story, Sub-task, Epic" },
        "priority" => { "type" => "string", "description" => "Priority name: Highest, High, Medium, Low, Lowest" },
        "assignee_id" => { "type" => "string", "description" => "Atlassian account ID for assignment" },
        "parent" => { "type" => "string", "description" => "Parent issue key for creating sub-tasks" },
        "labels" => { "type" => "string", "description" => "Comma-separated labels for create/update" },
        "body" => { "type" => "string", "description" => "Comment body text for add_comment" },
        "transition" => { "type" => "string", "description" => "Transition name (e.g., 'In Progress', 'Done'). Use list_transitions to see available options" },
        "limit" => { "type" => "integer", "description" => "Max results to return (default: 20, max: 50)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "trello",
    description: "Manage Trello boards, lists, and cards. Create, update, move, and archive cards. Add comments, labels, and members. Search across boards.",
    executor_type: "trello",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action to perform", "enum" => %w[list_boards get_board list_lists list_cards get_card create_card update_card move_card archive_card add_comment list_labels add_label remove_label list_members assign_member unassign_member search] },
        "board_id" => { "type" => "string", "description" => "Board ID (for get_board, list_lists, list_labels, list_members, search)" },
        "list_id" => { "type" => "string", "description" => "List ID (for list_cards, create_card, move_card)" },
        "card_id" => { "type" => "string", "description" => "Card ID (for get_card, update_card, move_card, archive_card, add_comment, add_label, remove_label, assign_member, unassign_member)" },
        "name" => { "type" => "string", "description" => "Card name (for create_card, update_card)" },
        "desc" => { "type" => "string", "description" => "Card description (for create_card, update_card)" },
        "text" => { "type" => "string", "description" => "Comment text (for add_comment)" },
        "due" => { "type" => "string", "description" => "Due date ISO 8601 (for create_card, update_card)" },
        "label_id" => { "type" => "string", "description" => "Label ID (for add_label, remove_label)" },
        "label_ids" => { "type" => "string", "description" => "Comma-separated label IDs (for create_card)" },
        "member_id" => { "type" => "string", "description" => "Member ID (for assign_member, unassign_member)" },
        "position" => { "type" => "string", "description" => "Card position: top or bottom (default: bottom)" },
        "query" => { "type" => "string", "description" => "Search query (for search)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "email",
    description: "Send emails via SMTP. Works with any email provider (Mailtrap, SendGrid, Mailgun, Amazon SES, etc). Supports plain text and HTML emails with CC, BCC, and reply-to.",
    executor_type: "email",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action to perform", "enum" => %w[send send_html config] },
        "to" => { "type" => "string", "description" => "Recipient email address(es), comma-separated for multiple" },
        "subject" => { "type" => "string", "description" => "Email subject line" },
        "body" => { "type" => "string", "description" => "Plain text email body (for send action)" },
        "html" => { "type" => "string", "description" => "HTML email body (for send_html action)" },
        "text" => { "type" => "string", "description" => "Plain text fallback for HTML emails (optional)" },
        "cc" => { "type" => "string", "description" => "CC recipients (optional)" },
        "bcc" => { "type" => "string", "description" => "BCC recipients (optional)" },
        "reply_to" => { "type" => "string", "description" => "Reply-to address (optional)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "pdf_read",
    description: "Read and extract content from PDF files using PyMuPDF. Supports text extraction, metadata reading, and table extraction. Can read specific page ranges and output as plain text or markdown with formatting preserved.",
    executor_type: "pdf_read",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: read (extract text), metadata (get PDF info), tables (extract tables)", "enum" => [ "read", "metadata", "tables" ] },
        "path" => { "type" => "string", "description" => "Path to the PDF file (absolute or relative to /workspace)" },
        "pages" => { "type" => "string", "description" => "Page range to extract (e.g., '1-5' or '3'). Omit for all pages." },
        "format" => { "type" => "string", "description" => "Output format: text (default) or markdown (preserves bold/italic/headings)", "enum" => [ "text", "markdown" ] },
        "page" => { "type" => "integer", "description" => "Specific page number for table extraction" }
      },
      "required" => [ "action", "path" ]
    }
  },
  {
    name: "coding_agent",
    description: "Delegate complex coding tasks to an autonomous coding agent (Claude Code, Codex, or Aider) running in the workspace. Best for multi-file changes, refactoring, adding features with tests, or fixing complex bugs. The coding agent runs in the background with real-time progress updates.",
    executor_type: "coding_agent",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "task" => { "type" => "string", "description" => "Detailed description of the coding task" },
        "cli" => { "type" => "string", "description" => "Coding CLI to use: claude (default), codex, or aider", "enum" => [ "claude", "codex", "aider" ] },
        "model" => { "type" => "string", "description" => "Model to use (CLI-specific, e.g. claude-sonnet, gpt-4o)" },
        "timeout" => { "type" => "integer", "description" => "Timeout in seconds (default: 600, max: 1800)" }
      },
      "required" => [ "task" ]
    }
  },
  {
    name: "coding_agent_status",
    description: "Check the status of running coding agent tasks, list recent tasks, or kill active tasks. Use the task_key returned by the coding_agent tool to monitor progress.",
    executor_type: "coding_agent_status",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: status (check one task), list (show recent tasks), or kill (terminate task)", "enum" => [ "status", "list", "kill" ] },
        "task_key" => { "type" => "string", "description" => "Task ID from coding_agent tool (required for status and kill actions)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "ask_user",
    description: "Pause execution and ask the user a clarifying question. The agent waits for the user's response before continuing. Use when you need user input to complete a task properly.",
    executor_type: "ask_user",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "question" => {
          "type" => "string",
          "description" => "The question to ask the user. Be specific and clear about what information you need."
        }
      },
      "required" => [ "question" ]
    }
  },
  {
    name: "grep",
    description: "Search for patterns in files using regular expressions. Search across the workspace or specific directories with optional case-insensitive matching.",
    executor_type: "grep",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "pattern" => { "type" => "string", "description" => "Regular expression pattern to search for" },
        "path" => { "type" => "string", "description" => "Directory path to search in (defaults to /workspace)" },
        "case_insensitive" => { "type" => "boolean", "description" => "Whether to perform case-insensitive search (default: false)" },
        "max_results" => { "type" => "integer", "description" => "Maximum number of results to return (default: 50)" }
      },
      "required" => [ "pattern" ]
    }
  },
  {
    name: "plan_mode",
    description: "Generate, manage, and execute multi-phase work plans. Create structured plans with objectives, approaches, and success criteria, then execute phase-by-phase.",
    executor_type: "plan_mode",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => {
          "type" => "string",
          "description" => "Action to perform: 'generate' to create a plan, 'execute' to start executing, or 'update_phase' to move to next phase",
          "enum" => [ "generate", "execute", "update_phase" ]
        },
        "task" => {
          "type" => "string",
          "description" => "Description of the task to plan (required for 'generate' action)"
        },
        "phase_number" => {
          "type" => "integer",
          "description" => "Phase number to move to (required for 'update_phase' action)"
        }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "glob",
    description: "Find files by name patterns using glob syntax. Use wildcards like *.rb, **/*.js, or test_*.py to find files matching specific patterns.",
    executor_type: "glob",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "pattern" => { "type" => "string", "description" => "Glob pattern to match files (e.g., '*.rb', '**/*.js', 'test_*.py')" },
        "path" => { "type" => "string", "description" => "Root directory to search from (defaults to /workspace)" }
      },
      "required" => [ "pattern" ]
    }
  },
  {
    name: "deep_research",
    description: "Perform multi-step, iterative deep research on a topic using web search, page fetching, and LLM analysis. Runs in the background with real-time progress updates. Returns a comprehensive research report.",
    executor_type: "deep_research",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "query" => { "type" => "string", "description" => "The research question or topic to investigate" },
        "depth" => { "type" => "string", "description" => "Research depth: quick (fast overview), standard (balanced), or deep (thorough)", "enum" => %w[quick standard deep] },
        "focus" => { "type" => "string", "description" => "Research focus area: general, technical, scientific, news, or financial", "enum" => %w[general technical scientific news financial] },
        "documents" => { "type" => "string", "description" => "Paths to local documents to include in analysis (comma-separated)" },
        "output_format" => { "type" => "string", "description" => "Output format: report, bullet_points, detailed_analysis, or executive_summary", "enum" => %w[report bullet_points detailed_analysis executive_summary] }
      },
      "required" => [ "query" ]
    }
  },
  {
    name: "deep_research_status",
    description: "Check the status of a deep research session, list recent sessions, or cancel an active session. Use the task_key returned by the deep_research tool.",
    executor_type: "deep_research_status",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: status (check one session), list (show recent), or cancel (stop active session)", "enum" => %w[status list cancel] },
        "task_key" => { "type" => "string", "description" => "Task ID from deep_research tool (required for status and cancel actions)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "canvas",
    description: "Render HTML content to a live canvas view alongside the chat. The canvas is a dedicated visual workspace that agents can update in real-time. Actions: render (full page), update (specific element by ID), append (add content), clear (reset).",
    executor_type: "canvas",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Canvas action: render, update, append, clear", "enum" => %w[render update append clear] },
        "html" => { "type" => "string", "description" => "HTML content to render, update, or append" },
        "title" => { "type" => "string", "description" => "Title for the canvas page (render action only)" },
        "element_id" => { "type" => "string", "description" => "DOM element ID to update (update action only)" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "stt",
    description: "Transcribe audio files to text using OpenAI Whisper API. Supports mp3, mp4, wav, webm, ogg, flac, m4a formats up to 25MB. Falls back to local whisper CLI if no API key is configured.",
    executor_type: "stt",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "file_path" => { "type" => "string", "description" => "Path to the audio file to transcribe" },
        "language" => { "type" => "string", "description" => "ISO language code (e.g., en, es, fr) to hint the language" }
      },
      "required" => [ "file_path" ]
    }
  },
  {
    name: "google_drive",
    description: "Search, read, create, and manage files in Google Drive via the gws CLI. Requires Google Workspace connection at /integrations.",
    executor_type: "google_drive",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: list, search, get, create, upload, download", "enum" => %w[list search get create upload download] },
        "query" => { "type" => "string", "description" => "Search query (for search action)" },
        "file_id" => { "type" => "string", "description" => "Google Drive file ID (for get/download)" },
        "name" => { "type" => "string", "description" => "File name (for create/upload)" },
        "mime_type" => { "type" => "string", "description" => "MIME type for create or export format for download" },
        "parent_id" => { "type" => "string", "description" => "Parent folder ID (for create/upload)" },
        "local_path" => { "type" => "string", "description" => "Local file path in workspace (for upload)" },
        "params" => { "type" => "object", "description" => "Additional gws parameters as key-value pairs" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "google_calendar",
    description: "List, create, update, and delete Google Calendar events via the gws CLI. Requires Google Workspace connection at /integrations.",
    executor_type: "google_calendar",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: list, get, create, update, delete, calendars", "enum" => %w[list get create update delete calendars] },
        "calendar_id" => { "type" => "string", "description" => "Calendar ID (defaults to 'primary')" },
        "event_id" => { "type" => "string", "description" => "Event ID (for get/update/delete)" },
        "summary" => { "type" => "string", "description" => "Event title (for create)" },
        "description" => { "type" => "string", "description" => "Event description (for create)" },
        "location" => { "type" => "string", "description" => "Event location (for create)" },
        "start_time" => { "type" => "string", "description" => "Start time in ISO 8601 format (for create)" },
        "end_time" => { "type" => "string", "description" => "End time in ISO 8601 format (for create)" },
        "timezone" => { "type" => "string", "description" => "Timezone (e.g. America/Chicago). Defaults to UTC" },
        "attendees" => { "type" => "array", "items" => { "type" => "string" }, "description" => "List of attendee email addresses (for create)" },
        "updates" => { "type" => "object", "description" => "Fields to update (for update action)" },
        "params" => { "type" => "object", "description" => "Additional gws parameters" }
      },
      "required" => [ "action" ]
    }
  },
  {
    name: "google_gmail",
    description: "Read, search, send, and draft emails via Google Gmail using the gws CLI. Requires Google Workspace connection with Gmail scope at /integrations.",
    executor_type: "google_gmail",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: list, get, search, send, draft", "enum" => %w[list get search send draft] },
        "message_id" => { "type" => "string", "description" => "Message ID (for get)" },
        "query" => { "type" => "string", "description" => "Gmail search query (for search)" },
        "to" => { "type" => "string", "description" => "Recipient email address (for send/draft)" },
        "subject" => { "type" => "string", "description" => "Email subject (for send/draft)" },
        "body" => { "type" => "string", "description" => "Email body text (for send/draft)" },
        "cc" => { "type" => "string", "description" => "CC recipients (for send/draft)" },
        "bcc" => { "type" => "string", "description" => "BCC recipients (for send/draft)" },
        "max_results" => { "type" => "integer", "description" => "Max messages to return (default: 20)" },
        "params" => { "type" => "object", "description" => "Additional gws parameters" }
      },
      "required" => [ "action" ]
    }
  },
  # ── Project Layer Tools ──────────────────────────────────────────
  {
    name: "project_update",
    description: "Manage projects and milestones. Update milestone status, edit project details, add/remove/edit milestones, and reassign agents.",
    executor_type: "project_update",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action to perform", "enum" => %w[update_milestone update_project add_milestone remove_milestone edit_milestone assign_agent], "default" => "update_milestone" },
        "project_id" => { "type" => "integer", "description" => "Project ID (for update_project and add_milestone)" },
        "milestone_id" => { "type" => "integer", "description" => "Milestone ID (for update_milestone, remove_milestone, edit_milestone, assign_agent)" },
        "title" => { "type" => "string", "description" => "Title (for update_project, add_milestone, edit_milestone)" },
        "description" => { "type" => "string", "description" => "Description (for update_project, add_milestone, edit_milestone)" },
        "acceptance_criteria" => { "type" => "string", "description" => "Acceptance criteria (for add_milestone, edit_milestone)" },
        "status" => { "type" => "string", "description" => "Milestone status (for update_milestone)", "enum" => %w[in_progress needs_review blocked] },
        "project_status" => { "type" => "string", "description" => "Project status (for update_project)", "enum" => %w[planning active paused] },
        "priority" => { "type" => "string", "description" => "Project priority (for update_project)", "enum" => %w[low normal high urgent] },
        "agent_name" => { "type" => "string", "description" => "Agent name to assign (for add_milestone, edit_milestone, assign_agent). Pass null to unassign." },
        "lead_agent_name" => { "type" => "string", "description" => "Lead agent name (for update_project)" },
        "requires_approval" => { "type" => "boolean", "description" => "Whether milestone requires approval (for add_milestone, edit_milestone)" },
        "notes" => { "type" => "string", "description" => "Summary of what was accomplished (for update_milestone)" },
        "deliverables" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Files, URLs, or summaries to attach (for update_milestone)" },
        "blocker" => { "type" => "string", "description" => "Blocker description (for update_milestone when status is blocked)" },
        "completed_steps" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Completed steps (for update_milestone)" },
        "pending_steps" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Pending steps (for update_milestone)" }
      },
      "required" => %w[action]
    }
  },
  {
    name: "project_list",
    description: "List all projects for your team. Use this to discover existing projects before creating new ones or to find a project ID.",
    executor_type: "project_list",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "status" => { "type" => "string", "description" => "Filter by status", "enum" => %w[planning active paused blocked completed] }
      },
      "required" => []
    }
  },
  {
    name: "project_status",
    description: "Check the current state of a project and its milestones. Returns progress, status of each milestone, and recent events. Use project_list first if you don't know the project ID.",
    executor_type: "project_status",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "project_id" => { "type" => "integer", "description" => "Project ID to check (use project_list to find IDs)" },
        "detail" => { "type" => "string", "description" => "Level of detail: summary or full", "enum" => %w[summary full] }
      },
      "required" => []
    }
  },
  {
    name: "project_create",
    description: "Propose a new project with milestones. Creates in planning status awaiting user approval.",
    executor_type: "project_create",
    requires_approval: true,
    parameters_schema: {
      "properties" => {
        "title" => { "type" => "string", "description" => "Project name" },
        "description" => { "type" => "string", "description" => "Goal description" },
        "milestones" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => {
              "title" => { "type" => "string" },
              "description" => { "type" => "string" },
              "acceptance_criteria" => { "type" => "string" },
              "agent_name" => { "type" => "string" },
              "requires_approval" => { "type" => "boolean" }
            },
            "required" => %w[title]
          },
          "description" => "Proposed milestone tree"
        },
        "priority" => { "type" => "string", "description" => "Suggested priority", "enum" => %w[low normal high urgent] }
      },
      "required" => %w[title description milestones]
    }
  },
  # ── Platform Control ───────────────────────────────────────────
  {
    name: "platform_control",
    description: "Manage the Hivemind platform itself. Restart services, update to latest version, check status, view logs.",
    executor_type: "platform_control",
    requires_approval: true,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action to perform", "enum" => %w[restart update status version logs] },
        "services" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Services to restart (e.g. app, worker, workspace). Omit to restart all. Only for restart action." },
        "rc" => { "type" => "boolean", "description" => "Include release candidates when updating. Only for update action." },
        "service" => { "type" => "string", "description" => "Service to fetch logs from (default: app). Only for logs action." },
        "lines" => { "type" => "integer", "description" => "Number of log lines to fetch (default: 50, max: 200). Only for logs action." }
      },
      "required" => %w[action]
    }
  },
  # ── Task Manager ──────────────────────────────────────────────
  {
    name: "task_manager",
    description: "Manage tasks on the shared team task board. Create, update, move, assign, list, comment on, close tasks, manage dependencies, checklists, hooks, and artifacts. Supports task templates for reusable workflows. Use 'activity' action to view the audit trail of all changes to a task.",
    executor_type: "task_manager",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => {
          "type" => "string",
          "description" => "Action to perform",
          "enum" => %w[create update move assign list my_tasks add_comment close add_dependency remove_dependency update_checklist add_hook remove_hook add_artifact remove_artifact activity]
        },
        "task_id" => { "type" => "integer", "description" => "Task ID (required for most actions except create, list, my_tasks)" },
        "title" => { "type" => "string", "description" => "Task title (required for create)" },
        "description" => { "type" => "string", "description" => "Task description" },
        "status" => { "type" => "string", "description" => "Task status", "enum" => %w[backlog todo in_progress review done] },
        "priority" => { "type" => "string", "description" => "Task priority", "enum" => %w[low medium high urgent] },
        "assign_to" => { "type" => "string", "description" => "Agent name or ID to assign the task to" },
        "due_at" => { "type" => "string", "description" => "Due date/time (ISO 8601 or natural language)" },
        "text" => { "type" => "string", "description" => "Comment text (required for add_comment)" },
        "limit" => { "type" => "integer", "description" => "Max results to return (default: 20, max: 50)" },
        "template" => { "type" => "string", "description" => "Task template name to apply on create" },
        "checklist" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Checklist items for create" },
        "depends_on_task_id" => { "type" => "integer", "description" => "Task ID to add/remove as dependency" },
        "checklist_action" => { "type" => "string", "description" => "Checklist sub-action: add or toggle", "enum" => %w[add toggle] },
        "item_title" => { "type" => "string", "description" => "Title for new checklist item (with checklist_action=add)" },
        "item_index" => { "type" => "integer", "description" => "Index of checklist item to toggle (with checklist_action=toggle)" },
        "skill_name" => { "type" => "string", "description" => "Skill name for add_hook" },
        "hook_trigger" => { "type" => "string", "description" => "Hook trigger: pre or post", "enum" => %w[pre post] },
        "hook_on_status" => { "type" => "string", "description" => "Status that triggers the hook", "enum" => %w[backlog todo in_progress review done] },
        "hook_config" => { "type" => "object", "description" => "Optional configuration for the hook" },
        "hook_id" => { "type" => "integer", "description" => "Hook ID for remove_hook" },
        "artifact_title" => { "type" => "string", "description" => "Artifact title (required for add_artifact)" },
        "artifact_url" => { "type" => "string", "description" => "Artifact URL (for add_artifact)" },
        "artifact_description" => { "type" => "string", "description" => "Artifact description (for add_artifact)" },
        "artifact_type" => { "type" => "string", "description" => "Artifact type (for add_artifact)", "enum" => %w[pr branch commit file url document other] },
        "artifact_id" => { "type" => "string", "description" => "Artifact ID (required for remove_artifact)" },
        "event_type" => { "type" => "string", "description" => "Filter activity by event type (for activity action)", "enum" => %w[status_change hook_fired comment_added assigned dependency_added dependency_removed checklist_updated created updated hook_added hook_removed artifact_added artifact_removed archived transition_requested pipeline_failed] },
        "since" => { "type" => "string", "description" => "Show activity since this timestamp, ISO 8601 (for activity action)" }
      },
      "required" => [ "action" ]
    }
  },
  # ── Chat Attachments ──────────────────────────────────────────
  {
    name: "chat_attachments",
    description: "List and download files that were uploaded to this chat session. Use 'list' to see all attachments, or 'download' to save one to the workspace for processing.",
    executor_type: "chat_attachments",
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action to perform", "enum" => %w[list download], "default" => "list" },
        "attachment_id" => { "type" => "integer", "description" => "ID of the attachment to download (required for download action)" }
      }
    }
  }
].freeze

BUILTIN_TOOLS.each do |tool_attrs|
  tool = Tool.find_or_initialize_by(name: tool_attrs[:name])
  tool.assign_attributes(tool_attrs.merge(builtin: true, enabled: true))
  tool.save!
  puts "  ✓ #{tool.name}"
end

puts "Built-in Tools seeded!"
