# frozen_string_literal: true

module Agents
  class ManageCron
    VALID_ACTIONS = %w[create update delete list].freeze

    def self.call(action:, agent:, **params)
      new(action:, agent:, **params).call
    end

    def initialize(action:, agent:, task_id: nil, schedule: nil, job_params: nil, name: nil, enabled: true)
      @action = action
      @agent = agent
      @task_id = task_id
      @schedule = schedule
      @job_params = job_params || {}
      @name = name
      @enabled = enabled
    end

    def call
      return ServiceResponse.failure(error: "Invalid action: #{@action}") unless VALID_ACTIONS.include?(@action)

      result = send("#{@action}_action")

      # Audit log
      AuditLog.create(
        actor_type: "Agent",
        actor_id: @agent.id,
        action: "cron_#{@action}",
        resource_type: "ScheduledTask",
        resource_id: result.dig(:data, :task)&.id,
        metadata: { action: @action, task_id: @task_id, schedule: @schedule }
      )

      result
    rescue StandardError => e
      ServiceResponse.failure(error: "Cron management failed: #{e.message}")
    end

    private

    def create_action
      return ServiceResponse.failure(error: "Schedule is required") if @schedule.blank?
      return ServiceResponse.failure(error: "Name is required") if @name.blank?

      task = ScheduledTask.create(
        agent_id: @agent.id,
        name: @name,
        schedule: @schedule,
        job_class: "AgentScheduledJob",
        job_params: @job_params,
        enabled: @enabled
      )

      if task.persisted?
        sync_to_sidekiq(task)
        ServiceResponse.success(data: { task: })
      else
        ServiceResponse.failure(error: task.errors.full_messages)
      end
    end

    def update_action
      return ServiceResponse.failure(error: "Task ID is required") if @task_id.blank?

      task = ScheduledTask.find_by(id: @task_id, agent_id: @agent.id)
      return ServiceResponse.failure(error: "Task not found") unless task

      update_params = {
        schedule: @schedule,
        job_params: @job_params,
        name: @name,
        enabled: @enabled
      }.compact

      if task.update(update_params)
        sync_to_sidekiq(task)
        ServiceResponse.success(data: { task: })
      else
        ServiceResponse.failure(error: task.errors.full_messages)
      end
    end

    def delete_action
      return ServiceResponse.failure(error: "Task ID is required") if @task_id.blank?

      task = ScheduledTask.find_by(id: @task_id, agent_id: @agent.id)
      return ServiceResponse.failure(error: "Task not found") unless task

      remove_from_sidekiq(task)
      task.destroy

      ServiceResponse.success(data: { task_id: @task_id, deleted: true })
    end

    def list_action
      tasks = ScheduledTask.where(agent_id: @agent.id).order(created_at: :desc)
      ServiceResponse.success(data: { tasks: tasks.as_json })
    end

    def sync_to_sidekiq(task)
      cron_name = "scheduled_task_#{task.id}"

      if task.enabled?
        Sidekiq::Cron::Job.create(
          name: cron_name,
          cron: task.schedule,
          class: task.job_class,
          args: [ task.id ]
        )
      else
        remove_from_sidekiq(task)
      end
    end

    def remove_from_sidekiq(task)
      cron_name = "scheduled_task_#{task.id}"
      Sidekiq::Cron::Job.destroy(cron_name)
    end
  end
end
