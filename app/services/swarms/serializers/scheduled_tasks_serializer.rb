# frozen_string_literal: true

module Swarms
  module Serializers
    # Converts ScheduledTask records into a swarm scheduled_tasks[] entry.
    #
    # Output schema per entry:
    #   name        – required (task name)
    #   schedule    – required (cron expression, e.g. "0 9 * * *")
    #   agent       – required (agent name the task belongs to)
    #   description – optional human-readable description
    #   enabled     – boolean (omitted when true — enabled is the default)
    #   params      – Hash of additional params (omitted when empty)
    #
    # Usage:
    #   hash = ScheduledTasksSerializer.call(scheduled_task: record)
    #   # => { "name" => "...", "schedule" => "...", "agent" => "...", ... }
    class ScheduledTasksSerializer
      def self.call(scheduled_task:)
        new(scheduled_task).call
      end

      def initialize(scheduled_task)
        @task = scheduled_task
      end

      def call
        hash = {
          "name"     => @task.name,
          "schedule" => @task.schedule,
          "agent"    => @task.agent.name
        }

        hash["description"] = @task.description if @task.description.present?

        # Only emit enabled: false — true is the default and omitting it keeps files clean.
        hash["enabled"] = false unless @task.enabled?

        hash["params"] = @task.params if @task.params.is_a?(Hash) && @task.params.any?

        hash
      end
    end
  end
end
