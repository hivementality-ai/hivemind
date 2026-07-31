# frozen_string_literal: true

# Nango and Composio are replaced by the Pipedream integration. Remove their
# seeded tools (dependent agent_tools/skill_tools/tool_executions are destroyed
# by the model associations) and their stored credentials.
class RemoveNangoAndComposio < ActiveRecord::Migration[8.0]
  def up
    Tool.where(name: %w[nango composio]).find_each(&:destroy)
    VaultEntry.where(namespace: %w[nango composio]).delete_all
  end

  def down
    # Tools are recreated by re-running db/seeds/tools.rb from a revision that
    # still contains them; credentials are not recoverable.
  end
end
