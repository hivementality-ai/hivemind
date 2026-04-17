# frozen_string_literal: true

module Swarms
  module Deployers
    # Creates or updates Agent records from a SwarmDocument's agents[] section,
    # then wires up skill and tool associations.
    #
    # Must run AFTER SkillsDeployer and ToolsDeployer so that the skill/tool
    # records referenced by agents already exist in the database.
    #
    # Each agent entry is a plain Hash (as produced by SwarmParser#normalize_array)
    # with the following relevant fields:
    #   name                  – required
    #   role                  – required
    #   soul / system_prompt  – optional (soul takes precedence)
    #   model                 – optional LLM model string
    #   model_config          – optional Hash of model parameters
    #   thinking_enabled      – optional boolean
    #   thinking_budget_tokens – optional integer
    #   thinking_visibility   – optional "hidden" | "debug"
    #   skills[]              – optional array of skill names to associate
    #   tools[]               – optional array of tool names to associate
    #
    # Resolution strategies are keyed by agent name:
    #   :skip      – keep existing agent and its associations unchanged
    #   :overwrite – update agent attributes and replace skill/tool associations
    #   :rename    – create new agent with auto-suffixed name, wire associations
    #   (none)     – create new agent (no conflict expected)
    #
    # Usage:
    #   result = AgentsDeployer.call(
    #     document:    swarm_doc,
    #     team:        team_record,      # may be nil
    #     resolutions: {}
    #   )
    #   result.success?          # => true / false
    #   result.payload[:agents]  # => [DeployResult, ...]
    class AgentsDeployer
      DeployResult = Data.define(:name, :record, :action) do
        # action is one of: :created, :updated, :skipped, :renamed
      end

      def self.call(document:, team: nil, resolutions: {})
        new(document, team, resolutions).call
      end

      def initialize(document, team, resolutions)
        @document    = document
        @team        = team
        @resolutions = resolutions.with_indifferent_access
      end

      def call
        results = @document.agents.map.with_index do |agent_hash, index|
          deploy_agent(agent_hash.with_indifferent_access, index)
        end

        ServiceResponse.success(payload: { agents: results })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: "Failed to deploy agents: #{e.record.errors.full_messages.join(', ')}")
      rescue StandardError => e
        ServiceResponse.error(message: "Failed to deploy agents: #{e.message}")
      end

      private

      def deploy_agent(agent_hash, _index)
        name     = agent_hash[:name].to_s
        strategy = @resolutions[name]&.to_sym
        existing = Agent.find_by(name: name)

        if existing.nil?
          record = create_agent(name, agent_hash)
          wire_associations(record, agent_hash)
          DeployResult.new(name: name, record: record, action: :created)
        else
          apply_strategy(strategy, existing, name, agent_hash)
        end
      end

      def create_agent(name, agent_hash)
        Agent.create!(build_attributes(name, agent_hash))
      end

      def apply_strategy(strategy, existing, name, agent_hash)
        case strategy
        when :skip
          DeployResult.new(name: name, record: existing, action: :skipped)
        when :overwrite
          existing.update!(build_attributes(name, agent_hash))
          replace_associations(existing, agent_hash)
          DeployResult.new(name: name, record: existing, action: :updated)
        when :rename
          new_name = unique_name(name)
          record   = create_agent(new_name, agent_hash.merge(name: new_name))
          wire_associations(record, agent_hash)
          DeployResult.new(name: new_name, record: record, action: :renamed)
        else
          # No resolution provided but conflict exists — skip to be safe.
          DeployResult.new(name: name, record: existing, action: :skipped)
        end
      end

      def build_attributes(name, agent_hash)
        attrs = {
          name:        name,
          role:        agent_hash[:role].to_s,
          system_prompt: resolve_system_prompt(agent_hash),
          enabled:     agent_hash.key?(:enabled) ? agent_hash[:enabled] : true
        }

        attrs[:team] = @team if @team.present?

        model = agent_hash[:model].presence
        attrs[:llm_model] = model if model.present?

        model_cfg = agent_hash[:model_config]
        attrs[:model_config] = model_cfg if model_cfg.is_a?(Hash)

        if agent_hash.key?(:thinking_enabled)
          attrs[:thinking_enabled] = agent_hash[:thinking_enabled]
        end

        if agent_hash[:thinking_budget_tokens].present?
          attrs[:thinking_budget_tokens] = agent_hash[:thinking_budget_tokens].to_i
        end

        if agent_hash[:thinking_visibility].present?
          attrs[:thinking_visibility] = agent_hash[:thinking_visibility].to_s
        end

        attrs
      end

      # soul (swarm field) maps to system_prompt on the Agent model.
      def resolve_system_prompt(agent_hash)
        agent_hash[:soul].presence || agent_hash[:system_prompt].presence
      end

      # Wire skill + tool associations on a freshly-created agent.
      def wire_associations(agent, agent_hash)
        attach_skills(agent, Array(agent_hash[:skills]))
        attach_tools(agent, Array(agent_hash[:tools]))
      end

      # Replace skill + tool associations on an overwritten agent.
      def replace_associations(agent, agent_hash)
        agent.agent_skills.destroy_all
        agent.agent_tools.destroy_all
        wire_associations(agent, agent_hash)
      end

      def attach_skills(agent, skill_names)
        return if skill_names.empty?

        skills = Skill.where(name: skill_names.map(&:to_s))
        skills.each do |skill|
          AgentSkill.find_or_create_by!(agent: agent, skill: skill)
        end
      end

      def attach_tools(agent, tool_names)
        return if tool_names.empty?

        tools = Tool.where(name: tool_names.map(&:to_s))
        tools.each do |tool|
          AgentTool.find_or_create_by!(agent: agent, tool: tool)
        end
      end

      # Appends an incrementing suffix until the name is unique.
      def unique_name(base)
        candidate = "#{base}-2"
        counter   = 2

        while Agent.exists?(name: candidate)
          counter  += 1
          candidate = "#{base}-#{counter}"
        end

        candidate
      end
    end
  end
end
