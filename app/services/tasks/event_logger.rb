# frozen_string_literal: true

module Tasks
  class EventLogger
    def self.call(task:, event_type:, summary:, agent: nil, metadata: {})
      TaskEvent.create!(
        task: task,
        agent: agent,
        event_type: event_type,
        summary: summary,
        metadata: metadata,
        created_at: Time.current
      )
    end
  end
end
