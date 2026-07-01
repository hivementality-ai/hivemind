# frozen_string_literal: true

module Skills
  # Rolls a skill back to a specific previous version.
  #
  # This replaces the skill's content with the content stored in the target
  # SkillVersion. A new SkillVersion is created with change_source "rollback"
  # so the history remains linear and auditable.
  class Rollback
    def self.call(skill:, version_number:, rolled_back_by:)
      new(skill:, version_number:, rolled_back_by:).call
    end

    def initialize(skill:, version_number:, rolled_back_by:)
      @skill           = skill
      @version_number  = version_number.to_i
      @rolled_back_by  = rolled_back_by
    end

    def call
      target = @skill.skill_versions.find_by(version_number: @version_number)
      return ServiceResponse.failure(error: "Version #{@version_number} not found for skill '#{@skill.name}'") unless target

      if target.content == @skill.content
        return ServiceResponse.failure(error: "Skill is already at this content — no rollback needed")
      end

      ActiveRecord::Base.transaction do
        @skill.skip_auto_snapshot!
        @skill.update!(content: target.content)

        SkillVersion.snapshot!(
          skill: @skill,
          change_source: "rollback",
          changed_by_user_id: @rolled_back_by,
          change_summary: "Rolled back to version #{@version_number}"
        )
      end

      ServiceResponse.success(data: {
        skill: @skill,
        rolled_back_to_version: @version_number,
        new_version_number: @skill.skill_versions.maximum(:version_number)
      })
    rescue StandardError => e
      Rails.logger.error("[Skills::Rollback] Failed for skill '#{@skill.name}': #{e.full_message}")
      ServiceResponse.failure(error: "Rollback failed: #{e.message}")
    end
  end
end
