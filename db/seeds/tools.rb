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
    description: "Navigate to a URL with a real browser (JavaScript rendering). Extracts page content or takes screenshots. Use when web_fetch fails on JS-heavy sites.",
    executor_type: "browser",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "url" => { "type" => "string", "description" => "URL to navigate to" },
        "action" => { "type" => "string", "description" => "Action: navigate (default) or screenshot", "enum" => [ "navigate", "screenshot" ] }
      },
      "required" => [ "url" ]
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
    description: "Manage scheduled tasks. Create recurring jobs, list existing schedules, delete or manually run tasks.",
    executor_type: "cron",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: list, create, delete, run", "enum" => %w[list create delete run] },
        "name" => { "type" => "string", "description" => "Task name (for create)" },
        "schedule" => { "type" => "string", "description" => "Cron expression or interval (for create)" },
        "command" => { "type" => "string", "description" => "Shell command to run (for create)" },
        "task_id" => { "type" => "string", "description" => "Task ID (for delete/run)" }
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
    description: "Delegate a task to another agent by name. The agent will process the task and return their response. Use to orchestrate work across teammates.",
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
    name: "spawn",
    description: "Spawn a sub-agent to handle a task in the background. Returns immediately with a task ID — you can keep working while the sub-agent runs. Use spawn_status to check on it later.",
    executor_type: "spawn",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "agent" => { "type" => "string", "description" => "Name of the agent to spawn" },
        "task" => { "type" => "string", "description" => "Task description for the sub-agent" }
      },
      "required" => %w[agent task]
    }
  },
  {
    name: "spawn_status",
    description: "Check the status of a spawned sub-agent task, or list recent sub-agent tasks.",
    executor_type: "spawn_status",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => { "type" => "string", "description" => "Action: status (check one task) or list (show recent tasks)", "enum" => %w[status list] },
        "task_key" => { "type" => "string", "description" => "Task ID from spawn (for status action)" }
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
    name: "plan_mode",
    description: "Enter or exit planning mode. In planning mode, tool calls are shown differently in the UI to indicate the agent is exploring and planning rather than implementing.",
    executor_type: "plan_mode",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "action" => {
          "type" => "string",
          "description" => "Action to perform: 'enter' to start planning mode, or 'exit' to end planning mode",
          "enum" => [ "enter", "exit" ]
        },
        "summary" => {
          "type" => "string",
          "description" => "Optional summary of the plan when exiting planning mode"
        }
      },
      "required" => [ "action" ]
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
