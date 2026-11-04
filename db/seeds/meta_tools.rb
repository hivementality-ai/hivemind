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
        "secrets" => {
          "type" => "object",
          "description" => "Secrets the script needs: { ENV_NAME: \"vault:namespace/key\" }. Pass vault references only, never the secret. The script reads $ENV_NAME."
        },
        "share_with_team" => { "type" => "boolean", "description" => "Share with teammates (default: false)" }
      },
      "required" => %w[name description script_template]
    }
  },
  {
    name: "create_connector",
    description: "Draft a connector for an HTTP API: base URL, auth scheme and a few operations. It is saved " \
                 "disabled; the user stores the key in the vault and approves it before it can run. " \
                 "Pass vault references only, never a secret.",
    executor_type: "create_connector",
    builtin: true,
    enabled: true,
    parameters_schema: {
      "properties" => {
        "name" => { "type" => "string", "description" => "Display name, e.g. Notion" },
        "slug" => { "type" => "string", "description" => "Short snake_case id used in tool names, e.g. notion" },
        "description" => { "type" => "string", "description" => "What the API is for" },
        "base_url" => { "type" => "string", "description" => "API base URL, https, no query string" },
        "auth_scheme" => {
          "type" => "string",
          "enum" => Connector::AUTH_SCHEMES,
          "description" => "How the API authenticates"
        },
        "auth_config" => {
          "type" => "object",
          "description" => "Secret fields as vault references like vault:notion/api_token (bearer: secret; " \
                           "api_key_header: header_name + secret; api_key_query: param_name + secret; " \
                           "basic: username + password). Never the secret itself."
        },
        "operations" => {
          "type" => "array",
          "description" => "3-6 operations, read-only first. Each: name (snake_case), description, method, " \
                           "path (starts with /, {placeholders} must be in params), params (JSON schema object), read_only (boolean)",
          "items" => { "type" => "object" }
        }
      },
      "required" => %w[name slug base_url auth_scheme auth_config operations]
    }
  }
]

meta_tools.each do |attrs|
  tool = Tool.find_or_initialize_by(name: attrs[:name])
  tool.assign_attributes(attrs)
  tool.save!
  Rails.logger.info("[Seeds] Meta-tool '#{tool.name}' #{tool.previously_new_record? ? 'created' : 'updated'}")
end
