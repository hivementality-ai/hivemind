# frozen_string_literal: true

module Tools
  class TaskManagerExecutor < BaseExecutor
    # Lightweight task management for agents.
    # All task data is stored in the tasks table (no external API required).

    def call
      action = input["action"].to_s.strip

      case action
      when "create"     then create_task
      when "update"     then update_task
      when "move"       then move_task
      when "assign"     then assign_task
      when "list"       then list_tasks
      when "my_tasks"   then my_tasks
      when "add_comment" then add_comment
      when "close"      then close_task
      else
        ServiceResponse.failure(
          error: "Unknown action: #{action}. Supported: create, update, move, assign, list, my_tasks, add_comment, close"
        )
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Task manager error: #{e.message}")
    end

    private

    # ─── Actions ───────────────────────────────────────────────────

    def create_task
      title = require_param!("title")

      task = Task.new(
        title:              title,
        description:        input["description"].presence,
        status:             valid_status(input["status"]) || "backlog",
        priority:           valid_priority(input["priority"]) || "medium",
        created_by_agent:   agent,
        due_at:             parse_date(input["due_at"])
      )

      if input["assign_to"].present?
        task.assigned_to_agent = find_agent(input["assign_to"])
      end

      task.save!
      ServiceResponse.success(data: { output: "Created task ##{task.id}: #{task.title} (#{task.status}/#{task.priority})" })
    end

    def update_task
      task = find_task!

      task.title       = input["title"]       if input["title"].present?
      task.description = input["description"] if input.key?("description")
      task.priority    = valid_priority(input["priority"]) if input["priority"].present?
      task.due_at      = parse_date(input["due_at"]) if input.key?("due_at")

      task.save!
      ServiceResponse.success(data: { output: "Updated task ##{task.id}: #{task.title}" })
    end

    def move_task
      task   = find_task!
      status = require_param!("status")

      unless Task::STATUSES.include?(status)
        return ServiceResponse.failure(error: "Invalid status '#{status}'. Valid: #{Task::STATUSES.join(', ')}")
      end

      old_status = task.status
      task.update!(status: status)

      ServiceResponse.success(data: { output: "Moved task ##{task.id} from '#{old_status}' to '#{status}'" })
    end

    def assign_task
      task     = find_task!
      assignee = find_agent(require_param!("assign_to"))

      task.update!(assigned_to_agent: assignee)
      ServiceResponse.success(data: { output: "Assigned task ##{task.id} to #{assignee.name}" })
    end

    def list_tasks
      scope = Task.all.by_priority.recent

      scope = scope.by_status(input["status"]) if input["status"].present?
      scope = scope.where(priority: input["priority"]) if input["priority"].present?

      if input["assigned_to"].present?
        target = find_agent(input["assigned_to"])
        scope = scope.for_agent(target)
      end

      limit = (input["limit"] || 20).to_i.clamp(1, 50)
      tasks = scope.limit(limit).includes(:assigned_to_agent, :created_by_agent)

      return ServiceResponse.success(data: { output: "No tasks found." }) if tasks.empty?

      lines = tasks.map(&:to_summary)
      ServiceResponse.success(data: { output: "Tasks (#{tasks.size}):\n\n#{lines.join("\n")}" })
    end

    def my_tasks
      unless agent
        return ServiceResponse.failure(error: "No agent context available")
      end

      tasks = Task.for_agent(agent).open.by_priority.recent
                  .includes(:created_by_agent)
                  .limit(20)

      return ServiceResponse.success(data: { output: "You have no open tasks." }) if tasks.empty?

      lines = tasks.map(&:to_summary)
      ServiceResponse.success(data: { output: "Your open tasks (#{tasks.size}):\n\n#{lines.join("\n")}" })
    end

    def add_comment
      task = find_task!
      body = require_param!("text")

      author = agent&.name || "Unknown"
      task.add_comment(author_name: author, body: body)

      ServiceResponse.success(data: { output: "Comment added to task ##{task.id}" })
    end

    def close_task
      task = find_task!
      task.update!(status: "done")
      ServiceResponse.success(data: { output: "Closed task ##{task.id}: #{task.title}" })
    end

    # ─── Helpers ───────────────────────────────────────────────────

    def require_param!(key)
      value = input[key].to_s.strip
      raise "#{key} is required" if value.empty?
      value
    end

    def find_task!
      id = require_param!("task_id")
      Task.find(id)
    rescue ActiveRecord::RecordNotFound
      raise "Task ##{id} not found"
    end

    def find_agent(name_or_id)
      agent = Agent.find_by(name: name_or_id) ||
              Agent.find_by(slug: name_or_id) ||
              Agent.find_by(id: name_or_id.to_i)
      raise "Agent '#{name_or_id}' not found" unless agent
      agent
    end

    def valid_status(val)
      val.presence && Task::STATUSES.include?(val) ? val : nil
    end

    def valid_priority(val)
      val.presence && Task::PRIORITIES.include?(val) ? val : nil
    end

    def parse_date(val)
      return nil if val.blank?
      Time.zone.parse(val.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
