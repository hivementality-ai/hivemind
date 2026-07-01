# frozen_string_literal: true

module Tools
  # Allows an agent to flag a skill as unhelpful after loading it.
  # Records the feedback on the most recent SkillLoadEvent for this agent/skill pair,
  # or creates a standalone feedback record if no load event exists.
  #
  # This signal is visible in the admin UI as an improvement prompt.
  class FlagSkillUnhelpfulExecutor
    def initialize(input:, config:, agent:)
      @input  = input
      @agent  = agent
      @config = config
    end

    def call
      skill_name = @input["skill_name"].to_s.strip
      reason     = @input["reason"].to_s.strip

      return ServiceResponse.failure(error: "skill_name is required") if skill_name.blank?
      return ServiceResponse.failure(error: "reason is required — describe what was missing or incorrect") if reason.blank?

      skill = Skill.find_by(name: skill_name)
      return ServiceResponse.failure(error: "Skill '#{skill_name}' not found") unless skill

      record_unhelpful_signal(skill, reason)

      ServiceResponse.success(data: {
        output: "Feedback recorded for skill '#{skill_name}'. Admins will review this improvement signal.",
        skill_name: skill_name
      })
    rescue StandardError => e
      Rails.logger.error("[FlagSkillUnhelpfulExecutor] Failed for '#{skill_name}': #{e.full_message}")
      ServiceResponse.failure(error: "Failed to record feedback: #{e.message}")
    end

    private

    def record_unhelpful_signal(skill, reason)
      session = @config&.dig(:session)

      # Prefer updating the most recent load event for this agent/skill to avoid
      # creating orphaned records when the agent loaded the skill in this session.
      recent_event = SkillLoadEvent
        .for_agent(@agent)
        .for_skill(skill)
        .where(was_helpful: [ nil, true ])
        .order(created_at: :desc)
        .first

      if recent_event
        recent_event.update!(was_helpful: false, flagged_reason: reason, flagged_at: Time.current)
      else
        SkillLoadEvent.create!(
          skill: skill,
          agent: @agent,
          session: session,
          load_tier: "manual",
          was_helpful: false,
          flagged_reason: reason,
          flagged_at: Time.current
        )
      end
    end
  end
end
