# frozen_string_literal: true

module Projects
  class MilestoneRunner
    def self.call(milestone:, resume: false)
      new(milestone: milestone, resume: resume).call
    end

    def initialize(milestone:, resume:)
      @milestone = milestone
      @resume = resume
    end

    def call
      agent = @milestone.agent
      return unless agent&.enabled?

      session = find_or_create_session(agent)

      # Always update the milestone's session reference
      updates = { session: session }
      unless @resume
        updates[:status] = "in_progress"
        updates[:started_at] = Time.current
      end
      @milestone.update!(updates)

      context = Projects::ContextBuilder.call(
        milestone: @milestone,
        resume: @resume
      )

      ChatStreamJob.perform_later(session.id, context, [])

      Projects::EventLogger.call(
        project: @milestone.project,
        milestone: @milestone,
        agent: agent,
        event_type: "milestone_started",
        summary: "Agent #{agent.name} #{@resume ? 'resumed' : 'started'} work on: #{@milestone.title}"
      )
    rescue StandardError => e
      Rails.logger.error("[MilestoneRunner] Failed for milestone #{@milestone.id}: #{e.message}")
    end

    private

    def find_or_create_session(agent)
      if @resume && @milestone.session&.persisted?
        # Create new session but carry forward the summary from the stalled one
        Session.create!(
          agent: agent,
          session_key: SecureRandom.uuid,
          title: "#{@milestone.project.title} — #{@milestone.title} (resumed)",
          status: "active",
          transcript: [],
          conversation_summary: @milestone.session.try(:conversation_summary),
          metadata: {
            type: "project_milestone",
            project_id: @milestone.project_id,
            milestone_id: @milestone.id,
            resumed_from_session: @milestone.session_id,
            resumed_at: Time.current.iso8601
          },
          last_activity_at: Time.current
        )
      else
        Session.create!(
          agent: agent,
          session_key: SecureRandom.uuid,
          title: "#{@milestone.project.title} — #{@milestone.title}",
          status: "active",
          transcript: [],
          metadata: {
            type: "project_milestone",
            project_id: @milestone.project_id,
            milestone_id: @milestone.id
          },
          last_activity_at: Time.current
        )
      end
    end
  end
end
