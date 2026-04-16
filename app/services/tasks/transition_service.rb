# frozen_string_literal: true

module Tasks
  class TransitionService
    def self.call(task:, new_status:, agent: nil, context: {})
      new(task: task, new_status: new_status, agent: agent, context: context).call
    end

    def initialize(task:, new_status:, agent:, context:)
      @task = task
      @new_status = new_status.to_s.strip
      @agent = agent
      @context = context
    end

    def call
      return ServiceResponse.failure(error: "Invalid status '#{@new_status}'") unless Task::STATUSES.include?(@new_status)
      return ServiceResponse.failure(error: "Task is already '#{@new_status}'") if @task.status == @new_status

      # Enforce dependencies for forward transitions (past backlog/todo)
      forward_statuses = %w[in_progress review done]
      if forward_statuses.include?(@new_status) && @task.blocked_by_dependencies?
        blockers = @task.blocking_tasks.where.not(status: "done").pluck(:id, :title)
        blocker_list = blockers.map { |id, title| "##{id} #{title}" }.join(", ")
        return ServiceResponse.failure(error: "Blocked by incomplete dependencies: #{blocker_list}")
      end

      # Enforce parent-child constraints
      if forward_statuses.include?(@new_status) && @task.subtask? && !@task.parent_allows_progress?
        parent = @task.parent
        return ServiceResponse.failure(
          error: "Parent task ##{parent.id} (#{parent.title}) must be at least in_progress before this subtask can move to '#{@new_status}'"
        )
      end

      if @new_status == "done" && @task.parent_task? && !@task.subtasks_complete?
        incomplete = @task.subtasks.where.not(status: "done").pluck(:id, :title)
        subtask_list = incomplete.map { |id, title| "##{id} #{title}" }.join(", ")
        return ServiceResponse.failure(
          error: "Cannot complete: subtasks still open: #{subtask_list}"
        )
      end

      # Run pre-hooks synchronously
      pre_result = run_pre_hooks
      return ServiceResponse.failure(error: "Pre-hook blocked transition: #{pre_result[:reason]}") if pre_result[:blocked]

      # Perform the transition
      old_status = @task.status
      @task.status = @new_status
      @task.save!

      # Log the event
      Tasks::EventLogger.call(
        task: @task,
        agent: @agent,
        event_type: "status_change",
        summary: "Status changed from '#{old_status}' to '#{@new_status}'",
        metadata: { from: old_status, to: @new_status }
      )

      # Enqueue post-hooks asynchronously
      TaskHookJob.perform_later(@task.id, @new_status, "post", @agent&.id, @context.to_json)

      ServiceResponse.success(data: { task: @task, old_status: old_status })
    rescue ActiveRecord::RecordInvalid => e
      ServiceResponse.failure(error: e.message)
    end

    private

    def run_pre_hooks
      hooks = @task.effective_hooks_for(@new_status, "pre")
      result = { blocked: false, reason: nil }

      hooks.each do |hook|
        outcome = Tasks::HookExecutor.call(
          hook: hook, task: @task, agent: @agent, context: @context
        )
        unless outcome.success?
          result[:blocked] = true
          result[:reason] = outcome.error
          break
        end
      end

      result
    end
  end
end
