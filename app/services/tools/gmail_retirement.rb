# frozen_string_literal: true

module Tools
  # Folds the retired IMAP `gmail` tool into `google_gmail`. Agents, skills,
  # agent configs and templates that named `gmail` end up on `google_gmail`
  # (never both), and the old tool row is disabled rather than deleted so its
  # execution history keeps resolving. Safe to run any number of times.
  class GmailRetirement
    OLD_NAME = "gmail"
    NEW_NAME = "google_gmail"

    # @return [void]
    def self.call
      new.call
    end

    def call
      old_tool = Tool.find_by(name: OLD_NAME)
      return unless old_tool

      new_tool = Tool.find_by(name: NEW_NAME)
      if new_tool
        move_assignments(AgentTool, :agent_id, old_tool, new_tool)
        move_assignments(SkillTool, :skill_id, old_tool, new_tool)
      end

      remap_names(Agent)
      remap_names(AgentTemplate)
      old_tool.update_columns(enabled: false, updated_at: Time.current)
    end

    private

    # Repoints each owner's assignment of the old tool at the new one, dropping
    # the old assignment when the owner already has the new tool.
    def move_assignments(join_model, owner_column, old_tool, new_tool)
      already_on_new = join_model.where(tool_id: new_tool.id).select(owner_column)
      join_model.where(tool_id: old_tool.id).where.not(owner_column => already_on_new).update_all(tool_id: new_tool.id)
      join_model.where(tool_id: old_tool.id).delete_all
    end

    # Rewrites `tools_config["enabled"]` name lists, deduplicating.
    def remap_names(model)
      model.where.not(tools_config: nil).find_each do |record|
        names = record.tools_config.is_a?(Hash) ? record.tools_config["enabled"] : nil
        next unless names.is_a?(Array) && names.include?(OLD_NAME)

        remapped = names.map { |n| n == OLD_NAME ? NEW_NAME : n }.uniq
        record.update_columns(tools_config: record.tools_config.merge("enabled" => remapped))
      end
    end
  end
end
