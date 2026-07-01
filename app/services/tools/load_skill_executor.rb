# frozen_string_literal: true

module Tools
  class LoadSkillExecutor
    def initialize(input:, config:, agent:)
      @input  = input
      @agent  = agent
      @config = config
    end

    def call
      skill_name = @input["name"].to_s.strip.downcase

      if skill_name.blank?
        return ServiceResponse.failure(error: "Please provide a skill name. Your available skills: #{available_skill_names}")
      end

      skill = @agent.skills.enabled.find { |s| s.name.downcase == skill_name }

      unless skill
        return ServiceResponse.failure(
          error: "Skill '#{skill_name}' not found. Your available skills: #{available_skill_names}"
        )
      end

      record_manual_load(skill)

      ServiceResponse.success(data: { output: skill.content })
    end

    private

    def available_skill_names
      @agent.skills.enabled.pluck(:name).join(", ")
    end

    def record_manual_load(skill)
      session = @config&.dig(:session)

      SkillLoadEvent.create!(
        skill: skill,
        agent: @agent,
        session: session,
        load_tier: "manual",
        relevance_score: nil,
        trigger_context: nil
      )
    rescue StandardError => e
      Rails.logger.warn("[LoadSkillExecutor] Failed to record manual load event for skill #{skill.id}: #{e.message}")
    end
  end
end
