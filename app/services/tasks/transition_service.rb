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
      return ServiceResponse.failure(error: "Task is currently being transitioned") if @task.transition_locked?

      # Enforce dependencies for forward transitions (past backlog/todo)
      forward_statuses = %w[in_progress review done]
      if forward_statuses.include?(@new_status) && @task.blocked_by_dependencies?
        blockers = @task.blocking_tasks.where.not(status: "done").pluck(:id, :title)
        blocker_list = blockers.map { |id, title| "##{id} #{title}" }.join(", ")
        return ServiceResponse.failure(error: "Blocked by incomplete dependencies: #{blocker_list}")
      end

      # Check if there are pre-hooks for this transition
      pre_hooks = @task.effective_hooks_for(@new_status, "pre")
      has_pre_hooks = pre_hooks.any?

      if has_pre_hooks
        # Full 3-phase pipeline: Pre → Transition → Post
        # PreTransitionJob will lock the task and run pre-hooks first.
        Tasks::PreTransitionJob.perform_later(
          @task.id, @new_status, @agent&.id, @context.to_json
        )

        Tasks::EventLogger.call(
          task: @task,
          agent: @agent,
          event_type: "transition_requested",
          summary: "Transition to '#{@new_status}' requested (3-phase pipeline with pre-hooks)",
          metadata: { target_status: @new_status, has_pre_hooks: true }
        )
      else
        # No pre-hooks — lock now and skip straight to TransitionJob.
        # This avoids an unnecessary job hop through PreTransitionJob.
        @task.lock_transition!(@agent)

        Tasks::TransitionJob.perform_later(
          @task.id, @new_status, @agent&.id, @context.to_json
        )

        Tasks::EventLogger.call(
          task: @task,
          agent: @agent,
          event_type: "transition_requested",
          summary: "Transition to '#{@new_status}' requested (skip-pre, no pre-hooks)",
          metadata: { target_status: @new_status, has_pre_hooks: false }
        )
      end

      ServiceResponse.success(data: { task: @task, pipeline: true, has_pre_hooks: has_pre_hooks })
    rescue ActiveRecord::RecordInvalid => e
      ServiceResponse.failure(error: e.message)
    end
  end
end
