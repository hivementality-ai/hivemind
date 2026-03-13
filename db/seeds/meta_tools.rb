# frozen_string_literal: true

# Meta-tools: allow agents to create their own tools and skills
# These are builtin tools that agents can use to extend their capabilities.

meta_tools = [
  {
    name: "create_skill",
    description: "Create a new reusable skill (instructions/knowledge) that can be loaded by agents. " \
                 "Clean skills are auto-approved; flagged ones require admin review.",
    executor_type: "create_skill",
    builtin: true,
    enabled: true,
    parameters_schema: {
      "properties" => {
        "name" => { "type" => "string", "description" => "Unique skill name (snake_case)" },
        "summary" => { "type" => "string", "description" => "One-line description (max 150 chars)" },
        "content" => { "type" => "string", "description" => "Full skill content in markdown" },
        "category" => {
          "type" => "string",
          "description" => "Skill category",
          "enum" => Skill::CATEGORIES
        },
        "share_with_team" => { "type" => "boolean", "description" => "Share with all teammates (default: false)" }
      },
      "required" => %w[name summary content]
    }
  },
  {
    name: "create_tool",
    description: "Create a new custom script tool with a bash template and parameter schema. " \
                 "All agent-created tools require admin approval before activation.",
    executor_type: "create_tool",
    builtin: true,
    enabled: true,
    parameters_schema: {
      "properties" => {
        "name" => { "type" => "string", "description" => "Unique tool name (snake_case)" },
        "description" => { "type" => "string", "description" => "What the tool does" },
        "script_template" => { "type" => "string", "description" => "Bash script with {{param}} placeholders" },
        "parameters" => { "type" => "object", "description" => "Parameter definitions: { name: { type, description, required } }" },
        "share_with_team" => { "type" => "boolean", "description" => "Share with teammates (default: false)" }
      },
      "required" => %w[name description script_template]
    }
  }
]

meta_tools.each do |attrs|
  tool = Tool.find_or_initialize_by(name: attrs[:name])
  tool.assign_attributes(attrs)
  tool.save!
  Rails.logger.info("[Seeds] Meta-tool '#{tool.name}' #{tool.previously_new_record? ? 'created' : 'updated'}")
end
