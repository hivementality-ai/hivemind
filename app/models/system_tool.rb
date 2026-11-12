# frozen_string_literal: true

# Virtual tool that behaves like a Tool record but isn't persisted.
# Used for system-level tools that are always available and hidden from UI.
class SystemTool
  attr_reader :name, :description, :executor_type, :parameters_schema

  def initialize(name:, description:, executor_type:, parameters_schema: {})
    @name = name
    @description = description
    @executor_type = executor_type
    @parameters_schema = parameters_schema
  end

  def to_llm_tool
    {
      name: name,
      description: description,
      input_schema: {
        type: "object",
        properties: parameters_schema["properties"] || {},
        required: parameters_schema["required"] || []
      }
    }
  end

  def enabled?
    true
  end

  def effective_config
    {}
  end

  def id
    "system_#{name}"
  end

  # System tools don't have DB records for executions — skip tracking
  def is_a?(klass)
    klass == Tool ? true : super
  end

  TALK_TO_TEAMMATE = SystemTool.new(
    name: "talk_to_teammate",
    description: "Request one bounded contribution from a teammate and receive their result in this team chat. Include the goal, sources or artifact links, expected output, and return owner. Use existing results; do not repeat requests, send acknowledgment-only messages, or call an agent waiting for you. The whole team shares a handoff limit.",
    executor_type: "talk_to_teammate",
    parameters_schema: {
      "properties" => {
        "teammate" => {
          "type" => "string",
          "description" => "Name of the teammate to talk to"
        },
        "message" => {
          "type" => "string",
          "description" => "The message to send to the teammate"
        }
      },
      "required" => [ "teammate", "message" ]
    }
  ).freeze

  LOAD_SKILL = SystemTool.new(
    name: "load_skill",
    description: "Load full instructions for one of your assigned skills. Call this when you need detailed guidance for a specific skill.",
    executor_type: "load_skill",
    parameters_schema: {
      "properties" => {
        "name" => {
          "type" => "string",
          "description" => "Name of the skill to load (e.g. 'github', 'trello', 'ticket-planning')"
        }
      },
      "required" => [ "name" ]
    }
  ).freeze

  FIND_TOOLS = SystemTool.new(
    name: "find_tools",
    description: "Search your connector and MCP tools by keyword. Returns matching tool names, descriptions and input schemas; call a match with use_tool.",
    executor_type: "find_tools",
    parameters_schema: {
      "properties" => {
        "query" => { "type" => "string", "description" => "Keywords describing what you want to do" },
        "limit" => { "type" => "integer", "description" => "Maximum matches to return (default 8)" }
      },
      "required" => [ "query" ]
    }
  ).freeze

  USE_TOOL = SystemTool.new(
    name: "use_tool",
    description: "Run a tool found with find_tools. Pass its exact name and its arguments.",
    executor_type: "use_tool",
    parameters_schema: {
      "properties" => {
        "name" => { "type" => "string", "description" => "Exact tool name from find_tools" },
        "arguments" => { "type" => "object", "description" => "Arguments matching the tool's input schema" }
      },
      "required" => [ "name" ]
    }
  ).freeze
end
