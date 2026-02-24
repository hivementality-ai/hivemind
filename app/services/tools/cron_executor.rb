# frozen_string_literal: true

module Tools
  class CronExecutor < BaseExecutor
    # Manage scheduled tasks — create (with confirmation), list, delete, run
    def call
      action = input["action"].to_s.strip

      case action
      when "list"
        list_tasks
      when "create", "add"
        create_task
      when "confirm_create"
        confirm_create_task
      when "delete", "remove"
        delete_task
      when "run"
        run_task
      else
        ServiceResponse.failure(error: "Unknown cron action: #{action}. Supported: list, create, confirm_create, delete, run")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Cron error: #{e.message}")
    end

    private

    def list_tasks
      tasks = ScheduledTask.order(created_at: :desc).limit(20)

      if tasks.any?
        output = tasks.map do |t|
          status = t.enabled? ? "✅" : "⏸️"
          frequency = CronParser.parse(t.schedule)
          "#{status} [#{t.id}] #{t.name} — #{frequency}"
        end.join("\n")
        ServiceResponse.success(data: { output: "Scheduled tasks:\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No scheduled tasks.", exit_code: 0 })
      end
    end

    def create_task
      name = input["name"].to_s.strip
      schedule = input["schedule"].to_s.strip
      job_class = input["job_class"].to_s.strip.presence || "ScheduledAgentJob"
      prompt = input["prompt"].to_s.strip
      job_params = input["job_params"].is_a?(Hash) ? input["job_params"] : {}
      job_params["prompt"] = prompt if prompt.present? && job_params["prompt"].blank?
      description_hint = input["description_hint"].to_s.strip
      confirm = input["confirm"].to_s.downcase != "false"

      # Validate required parameters
      return ServiceResponse.failure(error: "name required") if name.empty?
      return ServiceResponse.failure(error: "schedule required (cron expression)") if schedule.empty?

      # Two-stage confirmation flow
      if confirm
        # Stage 1: Generate explanation and return pending confirmation
        result = Agents::CronConfirmation.generate_explanation(
          agent: agent,
          name: name,
          schedule: schedule,
          job_class: job_class,
          job_params: job_params,
          description_hint: description_hint.presence
        )

        # Format as output string so the tool loop passes it to the LLM
        output = "Task '#{name}' prepared but NOT saved yet.\n" \
                 "Confirmation ID: #{result[:confirmation_id]}\n\n" \
                 "#{result[:next_step]}\n\n" \
                 "Details: #{result[:explanation].to_json}"
        ServiceResponse.success(data: { output: output, exit_code: 0 })
      else
        # Legacy mode: Create directly (for testing/trusted contexts)
        task = create_scheduled_task(name, schedule, job_class, job_params, description_hint)
        ServiceResponse.success(data: {
          status: "created",
          task_id: task.id,
          message: "#{task.name} scheduled ✅",
          next_run: task.next_run_at&.strftime("%Y-%m-%d %H:%M:%S %Z") || "Pending"
        })
      end
    end

    def confirm_create_task
      confirmation_id = input["confirmation_id"].to_s.strip
      return ServiceResponse.failure(error: "confirmation_id required") if confirmation_id.empty?

      result = Agents::CronConfirmation.confirm_and_persist(
        confirmation_id: confirmation_id,
        agent: agent
      )

      if result[:status] == "error"
        ServiceResponse.failure(error: result[:message])
      else
        ServiceResponse.success(data: { output: result[:message], exit_code: 0 })
      end
    end

    def delete_task
      task_id = input["task_id"].to_s.strip
      return ServiceResponse.failure(error: "task_id required") if task_id.empty?

      task = ScheduledTask.find(task_id)

      # Verify ownership
      return ServiceResponse.failure(error: "You do not own this task") unless task.agent_id == agent.id

      task.destroy!

      ServiceResponse.success(data: { output: "Deleted task: #{task.name}", exit_code: 0 })
    end

    def run_task
      task_id = input["task_id"].to_s.strip
      return ServiceResponse.failure(error: "task_id required") if task_id.empty?

      task = ScheduledTask.find(task_id)

      # Verify ownership
      return ServiceResponse.failure(error: "You do not own this task") unless task.agent_id == agent.id

      # Execute the job immediately
      begin
        job_class = resolve_job_class(task.job_class)
        return ServiceResponse.failure(error: "Unknown or disallowed job class: #{task.job_class}") unless job_class

        # Pass task ID as first argument for ScheduledAgentJob/SubAgentJob compatibility
        job_class.perform_now(task.id)

        ServiceResponse.success(data: {
          output: "Executed #{task.name} ✅",
          exit_code: 0
        })
      rescue NameError
        ServiceResponse.failure(error: "Job class not found: #{task.job_class}")
      rescue StandardError => e
        # Update task with error info
        task.update(
          last_run_at: Time.current,
          last_error_at: Time.current
        )

        ServiceResponse.failure(error: "Job execution failed: #{e.message}")
      end
    end

    ALLOWED_JOB_CLASSES = %w[
      ScheduledAgentJob
      ScheduledScriptJob
      SubAgentJob
    ].freeze

    def resolve_job_class(class_name)
      return nil unless ALLOWED_JOB_CLASSES.include?(class_name)

      class_name.constantize
    rescue NameError
      nil
    end

    def create_scheduled_task(name, schedule, job_class, job_params, description)
      ScheduledTask.create!(
        agent: agent,
        name: name,
        schedule: schedule,
        job_class: job_class,
        job_params: job_params,
        description: description.presence,
        confirmation_status: "active",
        enabled: true
      )
    end
  end
end
