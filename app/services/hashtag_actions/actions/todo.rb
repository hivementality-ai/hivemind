# frozen_string_literal: true

module HashtagActions
  module Actions
    class Todo < Base
      # Parses: #todo [high] Deploy auth flow @devon
      #   priority  — extracted from first [bracket] token matching a known priority
      #   assignee  — extracted from first @mention token
      #   title     — everything else, trimmed

      PRIORITY_PATTERN = /\[(?<priority>low|medium|high|urgent)\]/i
      ASSIGNEE_PATTERN = /@(?<name>\w+)/
      EMPTY_TITLE_MSG  = "Add what? Use: #todo [priority] <title> @agent"

      def execute
        return { response: EMPTY_TITLE_MSG, status: "no_payload" } if payload.blank?

        priority = extract_priority
        assignee = extract_assignee
        title    = clean_title

        return { response: EMPTY_TITLE_MSG, status: "no_payload" } if title.blank?

        task = Task.new(
          title:            title.truncate(255),
          status:           "backlog",
          priority:         priority,
          created_by_agent: agent,
          session:          session,
          metadata: {
            source:     "hashtag_action",
            session_id: session.id
          }
        )

        task.assigned_to_agent = assignee if assignee

        task.save!

        # Also keep a memory entry for semantic recall
        MemoryEntry.create!(
          agent: agent,
          content: "TODO: #{title}",
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

        msg = "Created task ##{task.id}: \"#{title.truncate(80)}\""
        msg += " [#{priority}]" unless priority == "medium"
        msg += " → assigned to #{assignee.name}" if assignee
        { response: msg, status: "created" }
      rescue StandardError => e
        { response: "Failed to create to-do: #{e.message}", status: "error" }
      end

      private

      def extract_priority
        match = payload.match(PRIORITY_PATTERN)
        match ? match[:priority].downcase : "medium"
      end

      def extract_assignee
        match = payload.match(ASSIGNEE_PATTERN)
        return nil unless match

        name = match[:name]
        Agent.find_by("LOWER(name) = ? OR LOWER(slug) = ?", name.downcase, name.downcase)
      end

      def clean_title
        payload
          .gsub(PRIORITY_PATTERN, "")
          .gsub(ASSIGNEE_PATTERN, "")
          .gsub(/\s+/, " ")
          .strip
      end
    end
  end
end
