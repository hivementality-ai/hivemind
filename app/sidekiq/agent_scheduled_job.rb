# frozen_string_literal: true

class AgentScheduledJob
  include Sidekiq::Job

  sidekiq_options queue: :scheduled, retry: 2

  def perform(scheduled_task_id)
    task = ScheduledTask.find(scheduled_task_id)
    agent = task.agent

    Rails.logger.info("Executing scheduled task #{task.id} for agent #{agent.name}")

    # Create a session for this scheduled execution
    session = Session.create!(
      key: "cron_#{task.id}_#{Time.current.to_i}",
      agent_id: agent.id,
      metadata: {
        source: "scheduled_task",
        scheduled_task_id: task.id,
        task_name: task.name,
        params: task.job_params
      },
      transcript: []
    )

    # Update last run time
    task.update(
      last_run_at: Time.current,
      run_count: task.run_count + 1
    )

    # Execute the scheduled task
    # This would integrate with your agent runtime to execute the task
    # The task.job_params could contain the actual work to be done
    execute_task_in_workspace(task, session)

    Rails.logger.info("Scheduled task #{task.id} completed successfully")
  rescue StandardError => e
    Rails.logger.error("AgentScheduledJob failed for task #{scheduled_task_id}: #{e.message}")
    task&.update(
      last_error: e.message,
      last_error_at: Time.current
    )
    raise
  end

  private

  def execute_task_in_workspace(task, session)
    # This is where the actual task execution would happen
    # It would run in the workspace container context
    # For now, we'll just log the execution
    Rails.logger.info("Task params: #{task.job_params}")
    
    # Future: integrate with agent runtime to execute commands/scripts
    # defined in task.job_params within the workspace container
  end
end
