# frozen_string_literal: true

module Projects
  class EventLogger
    def self.call(project:, event_type:, summary:, milestone: nil, agent: nil, user: nil, metadata: {})
      ProjectEvent.create!(
        project: project,
        project_milestone: milestone,
        agent: agent,
        user: user,
        event_type: event_type,
        summary: summary,
        metadata: metadata,
        created_at: Time.current
      )

      # Broadcast to project channel for real-time UI updates
      ActionCable.server.broadcast("project_#{project.id}", {
        type: "project_event",
        event_type: event_type,
        summary: summary,
        milestone_id: milestone&.id,
        agent_name: agent&.name,
        timestamp: Time.current.iso8601
      })
    end
  end
end
