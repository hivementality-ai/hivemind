# frozen_string_literal: true

module HashtagActions
  module Actions
    class Remember < Base
      def execute
        return { response: "What should I remember? Use: #remember <something>", status: "no_payload" } if payload.blank?

        MemoryEntry.create!(
          agent: agent,
          content: payload,
          source: session,
          memory_type: "preference",
          importance: 0.95,
          metadata: {
            source: "hashtag_action",
            stored_at: Time.current.iso8601,
            session_id: session.id
          }
        )

        # Force memory file refresh so the agent picks this up immediately
        Memory::FileSync.call(agent: agent, force: true)

        { response: "Remembered: \"#{payload.truncate(100)}\"", status: "stored" }
      rescue StandardError => e
        { response: "Failed to store memory: #{e.message}", status: "error" }
      end
    end
  end
end
