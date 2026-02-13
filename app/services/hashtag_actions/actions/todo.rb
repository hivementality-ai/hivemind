# frozen_string_literal: true

module HashtagActions
  module Actions
    class Todo < Base
      def execute
        return { response: "Add what? Use: #todo <task>", status: "no_payload" } if payload.blank?

        # Store as a memory with todo metadata for retrieval
        MemoryEntry.create!(
          agent: agent,
          content: "TODO: #{payload}",
          source: session,
          metadata: {
            source: "hashtag_action",
            type: "todo",
            status: "pending",
            stored_at: Time.current.iso8601,
            session_id: session.id
          }
        )

        # Also write to heartbeat checklist if the system assistant exists
        if (assistant = Agent.find_by(system_agent: true))
          checklist = Setting.get("heartbeat_checklist") || []
          checklist << {
            "task" => payload,
            "from_agent" => agent.name,
            "created_at" => Time.current.iso8601,
            "status" => "pending"
          }
          Setting.set("heartbeat_checklist", checklist)
        end

        { response: "Added to-do: \"#{payload.truncate(100)}\"", status: "created" }
      rescue StandardError => e
        { response: "Failed to create to-do: #{e.message}", status: "error" }
      end
    end
  end
end
