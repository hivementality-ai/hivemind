# frozen_string_literal: true

module Tools
  class TaskManagementExecutor < BaseExecutor
    VALID_STATUSES   = %w[backlog todo in_progress review done cancelled].freeze
    VALID_PRIORITIES = %w[low medium high urgent].freeze

    def call
      action = input["action"].to_s.strip
      return ServiceResponse.failure(error: missing_action_message) if action.blank?

      case action
      when "create_task"  then create_task
      when "update_task"  then update_task
      when "move_task"    then move_task
      when "assign_task"  then assign_task
      when "list_tasks"   then list_tasks
      when "my_tasks"     then my_tasks
      when "add_comment"  then add_comment
      when "close_task"   then close_task
      # Legacy aliases (kept for backwards compatibility)
      when "create"       then create_task
      when "list"         then list_tasks
      when "update"       then update_task
      when "close"        then close_task
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. #{missing_action_message}")
      end
    rescue ActiveRecord::RecordNotFound => e
      ServiceResponse.failure(error: "Not found: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      ServiceResponse.failure(error: "Validation failed: #{e.message}")
    rescue ArgumentError => e
      ServiceResponse.failure(error: e.message)
    rescue StandardError => e
      ServiceResponse.failure(error: "task_management error: #{e.message}")
    end

    private

    # ── Actions ──────────────────────────────────────────────────────────────

    def create_task
      title = input["title"].to_s.strip
      return ServiceResponse.failure(error: "title is required") if title.blank?

      team = resolve_team
      return ServiceResponse.failure(error: "Agent has no team — cannot create task") unless team

      attrs = {
        title: title,
        description: input["description"].to_s.presence,
        status: :todo,
        team: team,
        session: config[:session],
        created_by: "agent:#{agent&.slug}",
        created_by_agent: agent
      }

      attrs[:priority]              = validated_priority(input["priority"])   if input["priority"].present?
      attrs[:due_date]              = parse_due_date(input["due_date"])        if input["due_date"].present?
      attrs[:project_id]            = input["project_id"].to_i                 if input["project_id"].present?
      attrs[:project_milestone_id]  = input["project_milestone_id"].to_i       if input["project_milestone_id"].present?

      assign_to = input["assign_to"].presence || input["assignee"].presence
      if assign_to.present?
        assignee = resolve_agent(assign_to, team)
        return ServiceResponse.failure(error: "Agent '#{assign_to}' not found on this team") unless assignee
        attrs[:agent] = assignee
      end

      task = Task.create!(attrs.compact)
      ServiceResponse.success(data: { output: format_task(task, created: true) })
    end

    def update_task
      task = find_task(input["task_id"])

      attrs = {}
      attrs[:title]       = input["title"].strip             if input["title"].present?
      attrs[:description] = input["description"]             if input.key?("description")
      attrs[:due_date]    = parse_due_date(input["due_date"]) if input["due_date"].present?
      attrs[:priority]    = validated_priority(input["priority"]) if input["priority"].present?

      assign_to = input["assign_to"].presence || input["assignee"].presence
      if assign_to.present?
        assignee = resolve_agent(assign_to, task.team)
        return ServiceResponse.failure(error: "Agent '#{assign_to}' not found on team '#{task.team.name}'") unless assignee
        attrs[:agent] = assignee
      end

      return ServiceResponse.failure(error: "No fields to update") if attrs.empty?

      task.update!(attrs)
      ServiceResponse.success(data: { output: format_task(task) })
    end

    def move_task
      task       = find_task(input["task_id"])
      new_status = input["status"].to_s.strip

      return ServiceResponse.failure(error: "status is required") if new_status.blank?
      unless VALID_STATUSES.include?(new_status)
        return ServiceResponse.failure(error: "Invalid status '#{new_status}'. Valid: #{VALID_STATUSES.join(", ")}")
      end

      task.update!(status: new_status)
      ServiceResponse.success(data: { output: "Task ##{task.id} moved to #{new_status}. #{format_task(task)}" })
    end

    def assign_task
      task          = find_task(input["task_id"])
      assignee_name = (input["agent_name"] || input["assignee"]).to_s.strip

      if assignee_name.blank? || assignee_name.in?(%w[null unassign none])
        task.update!(agent: nil)
        return ServiceResponse.success(data: { output: "Task ##{task.id} unassigned." })
      end

      target_agent = if assignee_name == "me"
                       agent
                     else
                       resolve_agent(assignee_name, task.team)
                     end

      unless target_agent
        return ServiceResponse.failure(error: "Agent '#{assignee_name}' not found on team '#{task.team.name}'")
      end

      task.update!(agent: target_agent)
      ServiceResponse.success(data: { output: "Task ##{task.id} assigned to #{target_agent.name}. #{format_task(task)}" })
    end

    def list_tasks
      team = resolve_team
      return ServiceResponse.failure(error: "Agent has no team") unless team

      scope = Task.for_team(team).includes(:agent, :project_milestone)

      if input["status"].present?
        unless VALID_STATUSES.include?(input["status"])
          return ServiceResponse.failure(error: "Invalid status '#{input["status"]}'")
        end
        scope = scope.by_status(input["status"])
      end

      # Legacy "mine" boolean support + new "agent" string support
      if input["mine"] == true || input["mine"] == "true"
        scope = scope.assigned_to(agent)
      elsif input["agent"].present?
        filter_agent = resolve_agent(input["agent"], team)
        return ServiceResponse.failure(error: "Agent '#{input["agent"]}' not found") unless filter_agent
        scope = scope.assigned_to(filter_agent)
      end

      # Legacy "active" boolean: exclude done/cancelled
      unless input["active"] == false || input["active"] == "false"
        scope = scope.active if !input["status"].present? && !input.key?("active")
      end

      scope = scope.where(project_id: input["project_id"].to_i)                   if input["project_id"].present?
      scope = scope.where(project_milestone_id: input["project_milestone_id"].to_i) if input["project_milestone_id"].present?

      limit = (input["limit"] || 50).to_i.clamp(1, 100)
      tasks = scope.order(priority: :desc, created_at: :desc).limit(limit)

      return ServiceResponse.success(data: { output: "No tasks found." }) if tasks.empty?

      lines = tasks.map { |t| format_task_line(t) }
      ServiceResponse.success(data: { output: "#{tasks.size} task(s):\n#{lines.join("\n")}" })
    end

    def my_tasks
      return ServiceResponse.failure(error: "No agent context") unless agent

      tasks = Task.assigned_to(agent)
                  .active
                  .order(priority: :desc, due_date: :asc)
                  .limit(20)
                  .includes(:project_milestone)

      return ServiceResponse.success(data: { output: "No tasks assigned to you." }) if tasks.empty?

      overdue_count = tasks.count { |t| t.due_date.present? && t.due_date < Time.current }
      header = "Your tasks (#{tasks.size}#{overdue_count > 0 ? ", #{overdue_count} overdue" : ""}):"
      lines  = tasks.map { |t| format_task_line(t) }
      ServiceResponse.success(data: { output: "#{header}\n#{lines.join("\n")}" })
    end

    def add_comment
      task    = find_task(input["task_id"])
      comment = input["comment"].to_s.strip
      return ServiceResponse.failure(error: "comment is required") if comment.blank?

      comments = task.metadata.fetch("comments", [])
      comments << {
        "agent_id"   => agent&.id,
        "agent_name" => agent&.name || "unknown",
        "text"       => comment,
        "created_at" => Time.current.iso8601
      }
      task.update!(metadata: task.metadata.merge("comments" => comments))
      ServiceResponse.success(data: { output: "Comment added to task ##{task.id}." })
    end

    def close_task
      task = find_task(input["task_id"])
      note = input["resolution_note"].to_s.strip

      updates = { status: :done }
      if note.present?
        comments = task.metadata.fetch("comments", [])
        comments << {
          "agent_id"   => agent&.id,
          "agent_name" => agent&.name || "unknown",
          "text"       => "[Closed] #{note}",
          "created_at" => Time.current.iso8601
        }
        updates[:metadata] = task.metadata.merge("comments" => comments)
      end

      task.update!(updates)
      ServiceResponse.success(data: { output: "Task ##{task.id} closed. #{format_task(task)}" })
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def find_task(task_id)
      raise ArgumentError, "task_id is required" if task_id.blank?
      Task.find(task_id.to_i)
    end

    def resolve_team
      agent&.team
    end

    def resolve_agent(name_or_me, team)
      return agent if name_or_me == "me"
      team.agents.enabled.find_by("LOWER(name) = ?", name_or_me.downcase) ||
        team.agents.enabled.find_by("LOWER(slug) = ?", name_or_me.downcase)
    end

    def validated_priority(value)
      p = value.to_s.strip.downcase
      return p if VALID_PRIORITIES.include?(p)
      raise ArgumentError, "Invalid priority '#{value}'. Valid: #{VALID_PRIORITIES.join(", ")}"
    end

    def parse_due_date(value)
      Time.parse(value.to_s)
    rescue ArgumentError
      raise ArgumentError, "Invalid due_date '#{value}'. Use ISO 8601 (e.g. 2026-04-15T10:00:00Z)"
    end

    def format_task(task, created: false)
      prefix  = created ? "Created task" : "Task"
      overdue = task.due_date.present? && task.due_date < Time.current && !task.done? && !task.cancelled?
      due_str = task.due_date ? " due #{task.due_date.strftime("%Y-%m-%d")}#{overdue ? " (OVERDUE)" : ""}" : ""
      "#{prefix} ##{task.id}: \"#{task.title}\" [#{task.status}] [#{task.priority}]#{due_str} — #{task.agent&.name || "unassigned"}"
    end

    def format_task_line(task)
      overdue   = task.due_date.present? && task.due_date < Time.current && !task.done? && !task.cancelled?
      due_str   = task.due_date ? " due #{task.due_date.strftime("%m/%d")}#{overdue ? "!" : ""}" : ""
      ms_str    = task.project_milestone ? " [#{task.project_milestone.title.truncate(30)}]" : ""
      "##{task.id} [#{task.priority.upcase[0]}][#{task.status}] #{task.title.truncate(60)}#{ms_str}#{due_str} → #{task.agent&.name || "unassigned"}"
    end

    def missing_action_message
      "action is required. Valid: create_task, update_task, move_task, assign_task, list_tasks, my_tasks, add_comment, close_task"
    end
  end
end
