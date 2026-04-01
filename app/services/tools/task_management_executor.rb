# frozen_string_literal: true

module Tools
  class TaskManagementExecutor < BaseExecutor
    def call
      action = input["action"]
      case action
      when "create" then create_task
      when "list"   then list_tasks
      when "update" then update_task
      when "close"  then close_task
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Valid actions: create, list, update, close")
      end
    end

    private

    def create_task
      team = agent&.team
      return ServiceResponse.failure(error: "Agent has no team — can't create task") unless team

      task = Task.create!(
        title: input["title"].to_s.strip,
        description: input["description"],
        status: input["status"].presence || "todo",
        priority: input["priority"].presence || "medium",
        agent_id: resolve_agent_id(input["assignee"]),
        team: team,
        session: config[:session],
        created_by: "agent:#{agent.slug}"
      )

      ServiceResponse.success(data: { output: "Created task ##{task.id}: #{task.title} [#{task.status}]" })
    rescue ActiveRecord::RecordInvalid => e
      ServiceResponse.failure(error: "Failed to create task: #{e.message}")
    end

    def list_tasks
      team = agent&.team
      return ServiceResponse.failure(error: "Agent has no team — can't list tasks") unless team

      scope = team.tasks.includes(:agent)
      scope = scope.by_status(input["status"]) if input["status"].present?
      scope = scope.assigned_to(agent) if input["mine"] == true
      scope = scope.active unless input["active"] == false

      tasks = scope.order(priority: :desc, created_at: :desc).limit(input["limit"] || 20)

      if tasks.empty?
        return ServiceResponse.success(data: { output: "No tasks found." })
      end

      lines = tasks.map do |t|
        assignee = t.agent ? " → #{t.agent.name}" : ""
        "- ##{t.id} [#{t.status}] [#{t.priority}] #{t.title}#{assignee}"
      end

      ServiceResponse.success(data: { output: lines.join("\n") })
    rescue ArgumentError => e
      # Invalid enum value passed to by_status/by_priority
      ServiceResponse.failure(error: "Invalid filter value: #{e.message}")
    end

    def update_task
      task = Task.find_by(id: input["task_id"])
      return ServiceResponse.failure(error: "Task ##{input["task_id"]} not found") unless task

      attrs = {}
      attrs[:status]      = input["status"]      if input["status"].present?
      attrs[:priority]    = input["priority"]     if input["priority"].present?
      attrs[:title]       = input["title"]        if input["title"].present?
      attrs[:description] = input["description"]  if input["description"].present?
      attrs[:agent_id]    = resolve_agent_id(input["assignee"]) if input["assignee"].present?

      task.update!(attrs)
      ServiceResponse.success(data: { output: "Updated task ##{task.id}: #{task.title} [#{task.status}]" })
    rescue ActiveRecord::RecordInvalid => e
      ServiceResponse.failure(error: "Failed to update task: #{e.message}")
    end

    def close_task
      task = Task.find_by(id: input["task_id"])
      return ServiceResponse.failure(error: "Task ##{input["task_id"]} not found") unless task

      task.update!(status: :done, completed_at: Time.current)
      ServiceResponse.success(data: { output: "Closed task ##{task.id}: #{task.title}" })
    rescue ActiveRecord::RecordInvalid => e
      ServiceResponse.failure(error: "Failed to close task: #{e.message}")
    end

    def resolve_agent_id(name_or_slug)
      return agent&.id if name_or_slug.blank? || name_or_slug.to_s.strip == "me"

      found = Agent.find_by(slug: name_or_slug.to_s.parameterize(separator: "_")) ||
              Agent.where("LOWER(name) = ?", name_or_slug.to_s.downcase).first
      found&.id || agent&.id
    end
  end
end
