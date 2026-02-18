# frozen_string_literal: true

class AddVaultToolBindings < ActiveRecord::Migration[8.1]
  def change
    # Add tool_binding to vault entries — which tool this credential powers
    add_column :vault_entries, :tool_binding, :string, if_not_exists: true
    add_index :vault_entries, :tool_binding, if_not_exists: true

    # Add required_credentials to tools — what vault keys a tool needs
    add_column :tools, :required_credentials, :jsonb, default: [], if_not_exists: true

    # Add vault as valid executor_type
    # (handled by model validation, not migration)

    # Seed required_credentials for existing tools
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE tools SET required_credentials = '[
            {"namespace": "providers", "key": "openai_api_key", "description": "OpenAI API key"}
          ]'::jsonb WHERE executor_type = 'image_generate';
        SQL

        execute <<~SQL
          UPDATE tools SET required_credentials = '[
            {"namespace": "jira", "key": "base_url", "description": "Jira instance URL"},
            {"namespace": "jira", "key": "email", "description": "Jira account email"},
            {"namespace": "jira", "key": "api_token", "description": "Jira API token"}
          ]'::jsonb WHERE executor_type = 'jira';
        SQL

        execute <<~SQL
          UPDATE tools SET required_credentials = '[
            {"namespace": "google", "key": "gmail_address", "description": "Gmail address"},
            {"namespace": "google", "key": "gmail_app_password", "description": "Gmail app password"}
          ]'::jsonb WHERE executor_type = 'gmail';
        SQL

        execute <<~SQL
          UPDATE tools SET required_credentials = '[
            {"namespace": "github", "key": "token", "description": "GitHub personal access token"}
          ]'::jsonb WHERE executor_type = 'shell';
        SQL
      end
    end
  end
end
