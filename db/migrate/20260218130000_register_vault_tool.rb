# frozen_string_literal: true

class RegisterVaultTool < ActiveRecord::Migration[8.0]
  def up
    Tool.find_or_create_by!(name: "vault") do |t|
      t.description = "Manage credentials and secrets in the vault. Supports reading (redacted), checking existence, requesting writes (requires approval), listing keys, and checking tool credential status."
      t.executor_type = "vault"
      t.builtin = true
      t.enabled = true
      t.parameters_schema = vault_schema
    end
  end

  def down
    execute "DELETE FROM tools WHERE name = 'vault' AND builtin = true;"
  end

  private

  def vault_schema
    {
      "properties" => {
        "action" => {
          "type" => "string",
          "enum" => %w[read exists write confirm_write list_keys check_tool],
          "description" => "Vault action to perform"
        },
        "namespace" => {
          "type" => "string",
          "description" => "Credential namespace (e.g., 'providers', 'twilio', 'jira')"
        },
        "key" => {
          "type" => "string",
          "description" => "Credential key name"
        },
        "value" => {
          "type" => "string",
          "description" => "Credential value (only for write action)"
        },
        "purpose" => {
          "type" => "string",
          "description" => "Human-readable purpose of this credential (for write action)"
        },
        "tool_binding" => {
          "type" => "string",
          "description" => "Which tool this credential powers (for write action)"
        },
        "confirmation_id" => {
          "type" => "string",
          "description" => "Confirmation ID from a pending write (for confirm_write action)"
        },
        "tool_name" => {
          "type" => "string",
          "description" => "Tool name to check credentials for (for check_tool action)"
        }
      },
      "required" => %w[action]
    }
  end
end
