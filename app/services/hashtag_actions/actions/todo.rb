# frozen_string_literal: true

module HashtagActions
  module Actions
    class Todo < Base
      def execute
        return { response: "Add what? Use: #todo <task>", status: "no_payload" } if payload.blank?

        # Create a real Task record so it appears on the kanban board
        task = Task.create!(
          title:            payload.truncate(255),
          status:           "backlog",
          priority:         "medium",
          created_by_agent: agent,
          metadata: {
            source:     "hashtag_action",
            session_id: session.id
          }
        )

        # Also keep a memory entry for semantic recall
        MemoryEntry.create!(
          agent: agent,
          content: "TODO: #{payload}",
          source: session,
          metadata: {
            source:     "hashtag_action",
            type:       "todo",
            task_id:    task.id,
            status:     "pending",
            stored_at:  Time.current.iso8601,
            session_id: session.id
          }
        )

        { response: "Created task ##{task.id}: \"#{payload.truncate(100)}\"", status: "created" }
      rescue StandardError => e
        { response: "Failed to create to-do: #{e.message}", status: "error" }
      end
    end
  end
end
