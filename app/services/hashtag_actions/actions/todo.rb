# frozen_string_literal: true

module HashtagActions
  module Actions
    class Todo < Base
      def execute
        return { response: "Add what? Use: #todo <task>", status: "no_payload" } if payload.blank?
        return { response: "Agent has no team — can't create task.", status: "no_team" } unless agent.team

        task = Task.create!(
          title: payload,
          status: :todo,
          priority: :medium,
          agent: agent,
          team: agent.team,
          session: session,
          created_by: "hashtag"
        )

        # Backward compat: keep writing to heartbeat checklist during transition
        checklist = Setting.get("heartbeat_checklist") || []
        checklist << {
          "task" => payload,
          "task_id" => task.id,
          "from_agent" => agent.name,
          "created_at" => Time.current.iso8601,
          "status" => "pending"
        }
        Setting.set("heartbeat_checklist", checklist)

        { response: "Created task ##{task.id}: \"#{payload.truncate(100)}\"", status: "created" }
      rescue StandardError => e
        { response: "Failed to create task: #{e.message}", status: "error" }
      end
    end
  end
end
