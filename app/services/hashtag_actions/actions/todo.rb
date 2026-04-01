# frozen_string_literal: true

module HashtagActions
  module Actions
    # Parses #todo syntax and creates a Task record.
    #
    # Supported syntax:
    #   #todo Deploy auth flow
    #   #todo [high] Deploy auth flow
    #   #todo [urgent] Deploy auth flow @devon
    #   #todo Fix login bug @devon
    #
    class Todo < Base
      PRIORITY_PATTERN = /\A\[(?<priority>low|medium|high|urgent)\]\s*/i
      AGENT_PATTERN    = /\s+@(?<slug>[\w-]+)\z/i

      def execute
        return { response: "Add what? Use: #todo [priority] <task> @agent", status: "no_payload" } if payload.blank?
        return { response: "Agent has no team — can't create task.", status: "no_team" } unless agent.team

        title, priority, assignee = parse_payload(payload)

        if title.blank?
          return { response: "Task title can't be blank after parsing priority/assignee.", status: "no_payload" }
        end

        task = Task.create!(
          title: title,
          status: :todo,
          priority: priority,
          agent: assignee || agent,
          team: agent.team,
          session: session,
          created_by: "hashtag",
          created_by_agent: agent
        )

        assignee_note = assignee && assignee != agent ? " → assigned to #{assignee.name}" : ""
        { response: "Created task ##{task.id}: \"#{title.truncate(100)}\" [#{priority}]#{assignee_note}", status: "created" }
      rescue StandardError => e
        { response: "Failed to create task: #{e.message}", status: "error" }
      end

      private

      def parse_payload(raw)
        text = raw.strip

        # Extract optional [priority] prefix
        priority = :medium
        if (match = PRIORITY_PATTERN.match(text))
          priority = match[:priority].downcase.to_sym
          text = text.sub(PRIORITY_PATTERN, "")
        end

        # Extract optional @agent suffix
        assignee = nil
        if (match = AGENT_PATTERN.match(text))
          slug = match[:slug]
          assignee = agent.team.agents.enabled.find_by(slug: slug) ||
                     agent.team.agents.enabled.find_by("LOWER(name) = ?", slug.downcase)
          text = text.sub(AGENT_PATTERN, "") if assignee
        end

        [ text.strip, priority, assignee ]
      end
    end
  end
end
