# frozen_string_literal: true

module Swarms
  module Serializers
    # Converts an Agent record (plus its associations) into a swarm agents[] entry.
    #
    # The output hash maps directly to the schema defined in SwarmSchema#validate_agent:
    #   name                   – required
    #   role                   – required
    #   soul                   – system_prompt content (mapped from system_prompt column)
    #   model                  – llm_model string
    #   model_config           – Hash of model parameters (temperature, top_p, etc.)
    #   thinking_enabled       – boolean (omitted when false)
    #   thinking_budget_tokens – integer (omitted when thinking disabled)
    #   thinking_visibility    – "hidden" | "debug" (omitted when "hidden" / default)
    #   skills[]               – array of skill name strings (association references)
    #   tools[]                – array of tool name strings (association references)
    #   egress_policy          – egress policy hash (omitted when blank/default)
    #   tool_loop_config       – tool loop config hash (omitted when blank/default)
    #
    # Skills and tools are referenced by name, not embedded. The skill/tool content
    # lives in their own top-level sections of the swarm document.
    #
    # Usage:
    #   hash = AgentSerializer.call(agent: agent_record)
    #   # => { "name" => "...", "role" => "...", "skills" => ["skill-a"], ... }
    class AgentSerializer
      # Visibility value that is the system default — omit from output when set to this.
      DEFAULT_THINKING_VISIBILITY = "hidden"

      def self.call(agent:)
        new(agent).call
      end

      def initialize(agent)
        @agent = agent
      end

      def call
        hash = {
          "name" => @agent.name,
          "role" => @agent.role
        }

        hash["soul"]         = @agent.system_prompt if @agent.system_prompt.present?
        hash["model"]        = @agent.llm_model     if @agent.llm_model.present?
        hash["model_config"] = @agent.model_config  if serialize_model_config?

        serialize_thinking(hash)
        serialize_skills(hash)
        serialize_tools(hash)
        serialize_egress_policy(hash)
        serialize_tool_loop_config(hash)

        hash
      end

      private

      def serialize_model_config?
        cfg = @agent.model_config
        cfg.is_a?(Hash) && cfg.any?
      end

      def serialize_thinking(hash)
        if @agent.thinking_enabled?
          hash["thinking_enabled"]       = true
          hash["thinking_budget_tokens"] = @agent.thinking_budget_tokens if @agent.thinking_budget_tokens.present?
        end

        visibility = @agent.thinking_visibility.to_s
        if visibility.present? && visibility != DEFAULT_THINKING_VISIBILITY
          hash["thinking_visibility"] = visibility
        end
      end

      def serialize_skills(hash)
        skill_names = @agent.skills.order(:name).pluck(:name)
        hash["skills"] = skill_names if skill_names.any?
      end

      def serialize_tools(hash)
        tool_names = @agent.tools.order(:name).pluck(:name)
        hash["tools"] = tool_names if tool_names.any?
      end

      def serialize_egress_policy(hash)
        policy = @agent.egress_policy
        return if policy.blank? || !policy.is_a?(Hash)

        p = policy.with_indifferent_access
        return if p[:mode].blank?

        hash["egress_policy"] = policy
      end

      def serialize_tool_loop_config(hash)
        cfg = @agent.tool_loop_config
        return if cfg.blank? || !cfg.is_a?(Hash) || cfg.empty?

        # Only emit when it differs from the default loop config to keep swarm
        # files concise. An agent that uses all defaults produces no key.
        return if cfg == Agent::DEFAULT_LOOP_CONFIG.deep_stringify_keys

        hash["tool_loop_config"] = cfg
      end
    end
  end
end
