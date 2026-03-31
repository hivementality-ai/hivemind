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
    description: "Send a message to a specific teammate and get their response. Use this when you need input from a particular team member. You'll send them a message, they'll process it and respond, and you'll receive their answer.",
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
end
