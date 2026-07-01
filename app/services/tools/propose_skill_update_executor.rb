# frozen_string_literal: true

module Tools
  # Allows an agent to submit a diff-style improvement proposal for an existing skill.
  # The full proposed content replaces the current content upon approval.
  # No skill is modified until an admin reviews and approves.
  class ProposeSkillUpdateExecutor
    def initialize(input:, config:, agent:)
      @input  = input
      @agent  = agent
      @config = config
    end

    def call
      skill_name       = @input["skill_name"].to_s.strip
      proposed_content = @input["proposed_content"].to_s.strip
      rationale        = @input["rationale"].to_s.strip

      if skill_name.blank?
        return ServiceResponse.failure(error: "skill_name is required")
      end

      if proposed_content.blank?
        return ServiceResponse.failure(error: "proposed_content is required — provide the full updated skill text")
      end

      if rationale.blank?
        return ServiceResponse.failure(error: "rationale is required — explain what you improved and why")
      end

      result = Skills::UpdateProposer.call(
        agent: @agent,
        skill_name: skill_name,
        proposed_content: proposed_content,
        rationale: rationale
      )

      result
    end
  end
end
