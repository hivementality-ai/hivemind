# frozen_string_literal: true

module Tools
  class TaskManagerExecutor < BaseExecutor
    # Lightweight task management for agents.
    # All task data is stored in the tasks table (no external API required).

    def call
      action = input["action"].to_s.strip

      case action
      when "create"           then create_task
      when "update"           then update_task
      when "move"             then move_task
      when "assign"           then assign_task
      when "list"             then list_tasks
      when "my_tasks"         then my_tasks
      when "add_comment"      then add_comment
      when "close"            then close_task
      when "add_dependency"   then add_dependency
      when "remove_dependency" then remove_dependency
      when "update_checklist" then update_checklist
      when "add_hook"         then add_hook
      when "remove_hook"      then remove_hook
      else
        ServiceResponse.failure(
          error: "Unknown action: #{action}. Supported: create, update, move, assign, list, my_tasks, add_comment, close, add_dependency, remove_dependency, update_checklist, add_hook, remove_hook"
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

      task.assigned_to_agent = find_agent(input["assign_to"]) if input["assign_to"].present?

      # Optional linkage to project / milestone / session
      task.project           = find_project(input["project_id"])    if input["project_id"].present?
      task.project_milestone = find_milestone(input["milestone_id"]) if input["milestone_id"].present?
      task.session           = resolve_session(input["session_id"])  if input["session_id"].present?

      # Apply template if specified
      if input["template"].present?
        template = TaskTemplate.find_by!(name: input["template"])
        task.apply_template!(template)
      end

      # Add checklist items if provided
      if input["checklist"].is_a?(Array)
        task.checklist = input["checklist"].map { |item| { "title" => item.to_s, "checked" => false } }
      end

      task.save!

      Tasks::EventLogger.call(
        task: task,
        agent: agent,
        event_type: "created",
        summary: "Task created: #{task.title}"
      )

      ServiceResponse.success(data: { output: "Created task ##{task.id}: #{task.title} (#{task.status}/#{task.priority})" })
    end

    def update_task
      task = find_task!

      task.title       = input["title"]                    if input["title"].present?
      task.description = input["description"]              if input.key?("description")
      task.priority    = valid_priority(input["priority"]) if input["priority"].present?
      task.due_at      = parse_date(input["due_at"])       if input.key?("due_at")

      # Optional linkage updates
      task.project           = find_project(input["project_id"])     if input.key?("project_id")
      task.project_milestone = find_milestone(input["milestone_id"]) if input.key?("milestone_id")
      task.session           = resolve_session(input["session_id"])  if input.key?("session_id")

      task.save!
      ServiceResponse.success(data: { output: "Updated task ##{task.id}: #{task.title}" })
    end

    def move_task
      task   = find_task!
      status = require_param!("status")

      unless Task::STATUSES.include?(status)
        return ServiceResponse.failure(error: "Invalid status '#{status}'. Valid: #{Task::STATUSES.join(', ')}")
      end

      result = Tasks::TransitionService.call(task: task, new_status: status, agent: agent)
      return ServiceResponse.failure(error: result.error) unless result.success?

      ServiceResponse.success(data: { output: "Moved task ##{task.id} from '#{result.data[:old_status]}' to '#{status}'" })
    end

    def assign_task
      task     = find_task!
      assignee = find_agent(require_param!("assign_to"))

      task.update!(assigned_to_agent: assignee)

      Tasks::EventLogger.call(
        task: task,
        agent: agent,
        event_type: "assigned",
        summary: "Assigned to #{assignee.name}"
      )

      ServiceResponse.success(data: { output: "Assigned task ##{task.id} to #{assignee.name}" })
    end

    def list_tasks
      scope = Task.all.by_priority.recent

      scope = scope.by_status(input["status"])           if input["status"].present?
      scope = scope.where(priority: input["priority"])  if input["priority"].present?
      scope = scope.for_project(find_project(input["project_id"])) if input["project_id"].present?

      if input["assigned_to"].present?
        target = find_agent(input["assigned_to"])
        scope = scope.for_agent(target)
      end

      limit = (input["limit"] || 20).to_i.clamp(1, 50)
      tasks = scope.limit(limit).includes(:assigned_to_agent, :created_by_agent, :project)

      return ServiceResponse.success(data: { output: "No tasks found." }) if tasks.empty?

      lines = tasks.map(&:to_summary)
      ServiceResponse.success(data: { output: "Tasks (#{tasks.size}):\n\n#{lines.join("\n")}" })
    end

    def my_tasks
      unless agent
        return ServiceResponse.failure(error: "No agent context available")
      end

      tasks = Task.for_agent(agent).open.by_priority.recent
                  .includes(:created_by_agent, :project)
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

      Tasks::EventLogger.call(
        task: task,
        agent: agent,
        event_type: "comment_added",
        summary: "Comment added by #{author}"
      )

      ServiceResponse.success(data: { output: "Comment added to task ##{task.id}" })
    end

    def close_task
      task = find_task!

      result = Tasks::TransitionService.call(task: task, new_status: "done", agent: agent)
      return ServiceResponse.failure(error: result.error) unless result.success?

      ServiceResponse.success(data: { output: "Closed task ##{task.id}: #{task.title}" })
    end

    def add_dependency
      task = find_task!
      depends_on_id = require_param!("depends_on_task_id")
      depends_on = Task.find(depends_on_id)

      dep = TaskDependency.create!(task: task, depends_on: depends_on)

      Tasks::EventLogger.call(
        task: task,
        agent: agent,
        event_type: "dependency_added",
        summary: "Now blocked by task ##{depends_on.id}: #{depends_on.title}"
      )

      ServiceResponse.success(data: { output: "Task ##{task.id} now depends on task ##{depends_on.id}" })
    rescue ActiveRecord::RecordNotFound
      ServiceResponse.failure(error: "Task ##{depends_on_id} not found")
    end

    def remove_dependency
      task = find_task!
      depends_on_id = require_param!("depends_on_task_id")

      dep = task.task_dependencies.find_by!(depends_on_id: depends_on_id)
      dep.destroy!

      Tasks::EventLogger.call(
        task: task,
        agent: agent,
        event_type: "dependency_removed",
        summary: "No longer blocked by task ##{depends_on_id}"
      )

      ServiceResponse.success(data: { output: "Removed dependency on task ##{depends_on_id}" })
    rescue ActiveRecord::RecordNotFound
      ServiceResponse.failure(error: "Dependency not found")
    end

    def update_checklist
      task = find_task!
      sub_action = input["checklist_action"].to_s.strip

      case sub_action
      when "add"
        item_title = require_param!("item_title")
        task.add_checklist_item(item_title)

        Tasks::EventLogger.call(
          task: task, agent: agent, event_type: "checklist_updated",
          summary: "Checklist item added: #{item_title}"
        )

        ServiceResponse.success(data: { output: "Added checklist item to task ##{task.id}: #{item_title}" })
      when "toggle"
        index = input["item_index"].to_i
        if task.toggle_checklist_item(index)
          item = task.checklist[index]
          state = item["checked"] ? "checked" : "unchecked"

          Tasks::EventLogger.call(
            task: task, agent: agent, event_type: "checklist_updated",
            summary: "Checklist item #{state}: #{item['title']}"
          )

          ServiceResponse.success(data: { output: "Toggled checklist item #{index}: #{item['title']} (#{state})" })
        else
          ServiceResponse.failure(error: "Invalid checklist item index: #{index}")
        end
      else
        ServiceResponse.failure(error: "Unknown checklist_action: '#{sub_action}'. Use 'add' or 'toggle'")
      end
    end

    def add_hook
      task = find_task!
      skill_name = require_param!("skill_name")
      trigger = require_param!("hook_trigger")
      on_status = require_param!("hook_on_status")

      skill = Skill.enabled.find_by!(name: skill_name)

      hook = TaskHook.create!(
        task: task,
        skill: skill,
        trigger: trigger,
        on_status: on_status,
        config: input["hook_config"] || {},
        position: task.task_hooks.count
      )

      ServiceResponse.success(data: { output: "Added #{trigger}-hook on '#{on_status}' using skill '#{skill.name}' to task ##{task.id}" })
    rescue ActiveRecord::RecordNotFound
      ServiceResponse.failure(error: "Skill '#{skill_name}' not found")
    end

    def remove_hook
      task = find_task!
      hook_id = require_param!("hook_id")

      hook = task.task_hooks.find(hook_id)
      hook.destroy!

      ServiceResponse.success(data: { output: "Removed hook ##{hook_id} from task ##{task.id}" })
    rescue ActiveRecord::RecordNotFound
      ServiceResponse.failure(error: "Hook ##{hook_id} not found on this task")
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
      found = Agent.find_by(name: name_or_id) ||
              Agent.find_by(slug: name_or_id) ||
              Agent.find_by(id: name_or_id.to_i)
      raise "Agent '#{name_or_id}' not found" unless found
      found
    end

    def find_project(id_or_title)
      return nil if id_or_title.blank?

      Project.find_by(id: id_or_title.to_i) ||
        Project.find_by(title: id_or_title) ||
        raise("Project '#{id_or_title}' not found")
    end

    def find_milestone(id)
      return nil if id.blank?

      ProjectMilestone.find(id)
    rescue ActiveRecord::RecordNotFound
      raise "Milestone ##{id} not found"
    end

    def resolve_session(id)
      return nil if id.blank?

      Session.find(id)
    rescue ActiveRecord::RecordNotFound
      raise "Session ##{id} not found"
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
