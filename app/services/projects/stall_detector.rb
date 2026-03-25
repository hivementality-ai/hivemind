# frozen_string_literal: true

module Projects
  class StallDetector
    STALL_THRESHOLD = 45.minutes

    def self.call(project:)
      new(project: project).call
    end

    def initialize(project:)
      @project = project
    end

    def call
      @project.milestones.where(status: "in_progress").each do |milestone|
        next unless stalled?(milestone)

        Rails.logger.info("[StallDetector] Milestone #{milestone.id} appears stalled, triggering resume")

        Projects::EventLogger.call(
          project: @project,
          milestone: milestone,
          event_type: "context_resumed",
          summary: "Context reset detected. Resuming milestone with checkpoint."
        )

        Projects::MilestoneRunner.call(milestone: milestone, resume: true)
      end
    end

    private

    def stalled?(milestone)
      session = milestone.session
      return true unless session

      last_activity = session.last_activity_at || session.updated_at
      last_activity < STALL_THRESHOLD.ago
    end
  end
end
