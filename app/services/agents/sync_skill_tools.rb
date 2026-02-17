# frozen_string_literal: true

module Agents
  class SyncSkillTools
    def self.call(agent:, removed_skill_ids: [])
      new(agent:, removed_skill_ids:).call
    end

    def initialize(agent:, removed_skill_ids: [])
      @agent = agent
      @removed_skill_ids = removed_skill_ids
    end

    def call
      add_tools_from_skills
      remove_orphaned_tools

      ServiceResponse.success(data: { agent: @agent })
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to sync skill tools: #{e.message}")
    end

    private

    def add_tools_from_skills
      @agent.skills.includes(:tools).each do |skill|
        skill.tools.each do |tool|
          AgentTool.find_or_create_by(agent: @agent, tool:)
        end
      end
    end

    def remove_orphaned_tools
      return if @removed_skill_ids.empty?

      removed_skills = Skill.where(id: @removed_skill_ids).includes(:tools)
      remaining_tool_ids = @agent.skills.flat_map(&:tool_ids).uniq

      removed_skills.each do |skill|
        skill.tools.each do |tool|
          next if remaining_tool_ids.include?(tool.id)

          AgentTool.where(agent: @agent, tool:).destroy_all
        end
      end
    end
  end
end
