# frozen_string_literal: true

class TaskHookJob < ApplicationJob
  queue_as :default

  def perform(task_id, status, trigger, agent_id, context_json)
    task = Task.find(task_id)
    agent = agent_id ? Agent.find(agent_id) : nil
    context = JSON.parse(context_json)

    task.effective_hooks_for(status, trigger).each do |hook|
      Tasks::HookExecutor.call(hook: hook, task: task, agent: agent, context: context)
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("[TaskHookJob] Record not found: #{e.message}")
  end
end
