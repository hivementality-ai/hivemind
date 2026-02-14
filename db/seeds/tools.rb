# frozen_string_literal: true

puts "🔧 Seeding Built-in Tools..."

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
      "required" => ["command"]
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
      "required" => ["path"]
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
      "required" => ["path", "content"]
    }
  },
  {
    name: "web_search",
    description: "Search the web for information. Returns relevant results and snippets.",
    executor_type: "web_search",
    requires_approval: false,
    parameters_schema: {
      "properties" => {
        "query" => { "type" => "string", "description" => "Search query" }
      },
      "required" => ["query"]
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
      "required" => ["url"]
    }
  }
].freeze

BUILTIN_TOOLS.each do |tool_attrs|
  tool = Tool.find_or_initialize_by(name: tool_attrs[:name])
  tool.assign_attributes(tool_attrs.merge(builtin: true, enabled: true))
  tool.save!
  puts "  ✓ #{tool.name}"
end

puts "✅ Built-in Tools seeded!"
